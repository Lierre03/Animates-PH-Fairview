<?php
// Always return JSON
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Handle all PHP errors and exceptions as JSON
set_error_handler(function($errno, $errstr, $errfile, $errline) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => "PHP Error: $errstr in $errfile on line $errline"
    ]);
    exit;
});

set_exception_handler(function($e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => "Uncaught Exception: " . $e->getMessage()
    ]);
    exit;
});

require_once '../config/database.php';

$method = $_SERVER['REQUEST_METHOD'];

// JWT Helper functions
function getBearerToken() {
    $headers = getAuthorizationHeader();
    if (!empty($headers)) {
        if (preg_match('/Bearer\s(\S+)/', $headers, $matches)) {
            return $matches[1];
        }
    }
    return null;
}

function getAuthorizationHeader() {
    $headers = null;
    if (isset($_SERVER['Authorization'])) {
        $headers = trim($_SERVER["Authorization"]);
    } else if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        $headers = trim($_SERVER["HTTP_AUTHORIZATION"]);
    } elseif (function_exists('apache_request_headers')) {
        $requestHeaders = apache_request_headers();
        $requestHeaders = array_combine(array_map('ucwords', array_keys($requestHeaders)), array_values($requestHeaders));
        if (isset($requestHeaders['Authorization'])) {
            $headers = trim($requestHeaders['Authorization']);
        }
    }
    return $headers;
}

function verifyJWT($token) {
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        throw new Exception('Invalid token format');
    }
    
    $header = json_decode(base64_decode(str_replace(['-', '_'], ['+', '/'], $parts[0])));
    $payload = json_decode(base64_decode(str_replace(['-', '_'], ['+', '/'], $parts[1])));
    $signature = str_replace(['-', '_'], ['+', '/'], $parts[2]);
    
    $expectedSignature = hash_hmac('sha256', $parts[0] . "." . $parts[1], getJWTSecret(), true);
    
    if (!hash_equals($expectedSignature, base64_decode($signature))) {
        throw new Exception('Invalid signature');
    }
    
    if ($payload->exp < time()) {
        throw new Exception('Token expired');
    }
    
    return $payload;
}

function getJWTSecret() {
    return '8paws_jwt_secret_key_2025';
}

function requireAuth() {
    $token = getBearerToken();
    if (!$token) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'No token provided']);
        exit;
    }
    
    try {
        $decoded = verifyJWT($token);
        return $decoded;
    } catch(Exception $e) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Invalid token']);
        exit;
    }
}

if ($method === 'GET') {
    $action = $_GET['action'] ?? '';
    
    switch($action) {
        case 'get_staff':
            handleGetStaff();
            break;
        case 'get_services':
            handleGetServices();
            break;
        default:
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Invalid action']);
            break;
    }
} elseif ($method === 'POST') {
    $rawInput = file_get_contents('php://input');
    $input = json_decode($rawInput, true);
    
    if (json_last_error() !== JSON_ERROR_NONE) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Invalid JSON']);
        exit;
    }
    
    $action = $input['action'] ?? '';
    
    switch($action) {
        case 'book_appointment':
            handleBookAppointment($input);
            break;
        default:
            http_response_code(400);
            echo json_encode(['success' => false, 'error' => 'Invalid action']);
            break;
    }
} else {
    http_response_code(405);
    echo json_encode(['success' => false, 'error' => 'Method not allowed']);
}

function handleGetStaff() {
    requireAuth();
    
    try {
        $db = getDB();
        $stmt = $db->prepare("SELECT id, first_name, last_name FROM users WHERE role = 'staff' AND is_active = 1 ORDER BY first_name, last_name");
        $stmt->execute();
        $staff = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        echo json_encode([
            'success' => true,
            'data' => $staff
        ]);
    } catch(Exception $e) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => $e->getMessage()]);
    }
}

function handleGetServices() {
    requireAuth();
    
    try {
        $db = getDB();
        $stmt = $db->prepare("SELECT id, name, price, category, description FROM services WHERE is_active = 1 ORDER BY category, name");
        $stmt->execute();
        $services = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        echo json_encode([
            'success' => true,
            'data' => $services
        ]);
    } catch(Exception $e) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => $e->getMessage()]);
    }
}

function handleBookAppointment($input) {
    $decoded = requireAuth();
    
    try {
        $db = getDB();
        
        // Validate required fields
        $required = ['petName', 'petType', 'petBreed', 'preferredDate', 'preferredTime', 'services'];
        foreach ($required as $field) {
            if (!isset($input[$field]) || empty($input[$field])) {
                throw new Exception(ucfirst($field) . ' is required');
            }
        }
        
        // Validate services array
        if (!is_array($input['services']) || empty($input['services'])) {
            throw new Exception('At least one service must be selected');
        }
        
        // Validate date is not in the past
        $appointmentDate = $input['preferredDate'];
        if (strtotime($appointmentDate) < strtotime(date('Y-m-d'))) {
            throw new Exception('Appointment date cannot be in the past');
        }
        
        $db->beginTransaction();
        
        // Get or create customer record
        $stmt = $db->prepare("SELECT id FROM customers WHERE user_id = ?");
        $stmt->execute([$decoded->user_id]);
        $customer = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$customer) {
            // Get user info to create customer record
            $stmt = $db->prepare("SELECT first_name, last_name, phone, email, address, emergency_contact_name, emergency_contact_no FROM users WHERE id = ?");
            $stmt->execute([$decoded->user_id]);
            $userInfo = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if (!$userInfo) {
                throw new Exception('User not found');
            }
            
            // Create customer record
            $stmt = $db->prepare("
                INSERT INTO customers (name, phone, email, address, emergency_contact, user_id, created_via) 
                VALUES (?, ?, ?, ?, ?, ?, 'online')
            ");
            $stmt->execute([
                $userInfo['first_name'] . ' ' . $userInfo['last_name'],
                $userInfo['phone'],
                $userInfo['email'],
                $userInfo['address'],
                $userInfo['emergency_contact_name'] . ' - ' . $userInfo['emergency_contact_no'],
                $decoded->user_id
            ]);
            
            $customerId = $db->lastInsertId();
        } else {
            $customerId = $customer['id'];
        }
        
        // Create or get pet record
        $stmt = $db->prepare("
            SELECT id FROM pets 
            WHERE customer_id = ? AND name = ? AND type = ? AND breed = ?
        ");
        $stmt->execute([$customerId, $input['petName'], $input['petType'], $input['petBreed']]);
        $pet = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$pet) {
            // Create new pet record
            $stmt = $db->prepare("
                INSERT INTO pets (customer_id, name, type, pet_type, breed, age_range, size, special_notes) 
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ");
            $stmt->execute([
                $customerId,
                $input['petName'],
                $input['petType'],
                $input['petType'], // pet_type same as type
                $input['petBreed'],
                $input['petAge'] ?? null,
                $input['petSize'] ?? null,
                $input['specialInstructions'] ?? null
            ]);
            
            $petId = $db->lastInsertId();
        } else {
            $petId = $pet['id'];
            
            // Update pet info if needed
            $stmt = $db->prepare("
                UPDATE pets 
                SET age_range = ?, size = ?, special_notes = ? 
                WHERE id = ?
            ");
            $stmt->execute([
                $input['petAge'] ?? null,
                $input['petSize'] ?? null,
                $input['specialInstructions'] ?? null,
                $petId
            ]);
        }
        
        // Get service prices and calculate total
        $serviceIds = array_map('intval', $input['services']);
        $placeholders = str_repeat('?,', count($serviceIds) - 1) . '?';
        
        $stmt = $db->prepare("SELECT id, price, duration_minutes FROM services WHERE id IN ($placeholders)");
        $stmt->execute($serviceIds);
        $services = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        if (count($services) !== count($serviceIds)) {
            throw new Exception('Some selected services are not available');
        }
        
        $totalAmount = array_sum(array_column($services, 'price'));
        $totalDuration = array_sum(array_column($services, 'duration_minutes'));
        
        // Create appointment
        $stmt = $db->prepare("
            INSERT INTO appointments (user_id, pet_id, appointment_date, appointment_time, estimated_duration, total_amount, special_instructions, status) 
            VALUES (?, ?, ?, ?, ?, ?, ?, 'scheduled')
        ");
        $stmt->execute([
            $decoded->user_id,
            $petId,
            $appointmentDate,
            $input['preferredTime'],
            $totalDuration,
            $totalAmount,
            $input['specialInstructions'] ?? null
        ]);
        
        $appointmentId = $db->lastInsertId();
        
        // Add appointment services
        $stmt = $db->prepare("INSERT INTO appointment_services (appointment_id, service_id, price) VALUES (?, ?, ?)");
        foreach ($services as $service) {
            $stmt->execute([$appointmentId, $service['id'], $service['price']]);
        }
        
        $db->commit();
        
        echo json_encode([
            'success' => true,
            'appointment_id' => $appointmentId,
            'message' => 'Appointment booked successfully!',
            'data' => [
                'appointment_id' => $appointmentId,
                'date' => $appointmentDate,
                'time' => $input['preferredTime'],
                'pet_name' => $input['petName'],
                'total_amount' => $totalAmount
            ]
        ]);
        
    } catch(Exception $e) {
        if (isset($db) && $db->inTransaction()) {
            $db->rollback();
        }
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => $e->getMessage()]);
    }
}
?>