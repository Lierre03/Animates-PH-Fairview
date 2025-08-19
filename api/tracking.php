<?php
// Always return JSON
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
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

if ($method === 'GET') {
    // Check if user is authenticated
    $token = getBearerToken();
    if (!$token) {
        http_response_code(401);
        echo json_encode([
            'success' => false,
            'error' => 'Authentication required'
        ]);
        exit;
    }

    try {
        $decoded = verifyJWT($token);
        $userEmail = $decoded->email;
        
        // Check if user has customer role
        $db = getDB();
        $stmt = $db->prepare("SELECT role FROM users WHERE email = ? AND role = 'customer'");
        $stmt->execute([$userEmail]);
        if (!$stmt->fetch()) {
            http_response_code(403);
            echo json_encode([
                'success' => false,
                'error' => 'Access denied. Customer role required.'
            ]);
            exit;
        }

        // Get specific RFID if provided
        $rfid = $_GET['rfid'] ?? '';

        if ($rfid) {
            handleSpecificRFIDTracking($rfid, $userEmail);
        } else {
            handleUserBookings($userEmail);
        }

    } catch (Exception $e) {
        http_response_code(401);
        echo json_encode([
            'success' => false,
            'error' => 'Invalid authentication token'
        ]);
        exit;
    }
} else {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'error' => 'Method not allowed'
    ]);
}
exit;

function handleUserBookings($userEmail) {
    try {
        $db = getDB();
        
        // Get all active bookings for the logged-in user
        $stmt = $db->prepare("
            SELECT 
                b.id as booking_id,
                b.custom_rfid as tag_id,
                b.status,
                b.total_amount,
                b.check_in_time,
                b.estimated_completion,
                b.actual_completion,
                p.name as pet_name,
                p.breed,
                c.name as owner_name,
                GROUP_CONCAT(CONCAT(s.name, '|', bs.price) SEPARATOR '|||') as services
            FROM bookings b
            JOIN pets p ON b.pet_id = p.id
            JOIN customers c ON p.customer_id = c.id
            LEFT JOIN booking_services bs ON b.id = bs.booking_id
            LEFT JOIN services s ON bs.service_id = s.id
            WHERE c.email = ? 
            AND b.status IN ('checked-in', 'bathing', 'grooming', 'ready')
            GROUP BY b.id
            ORDER BY b.check_in_time DESC
        ");
        $stmt->execute([$userEmail]);
        $bookings = $stmt->fetchAll(PDO::FETCH_ASSOC);

        $processedBookings = [];
        foreach ($bookings as $booking) {
            $services = [];
            if ($booking['services']) {
                $serviceData = explode('|||', $booking['services']);
                foreach ($serviceData as $service) {
                    $parts = explode('|', $service);
                    if (count($parts) == 2) {
                        $services[] = [
                            'name' => $parts[0],
                            'price' => $parts[1]
                        ];
                    }
                }
            }

            // Get status history
            $historyStmt = $db->prepare("
                SELECT status, created_at 
                FROM status_updates 
                WHERE booking_id = ? 
                ORDER BY created_at ASC
            ");
            $historyStmt->execute([$booking['booking_id']]);
            $statusHistory = $historyStmt->fetchAll(PDO::FETCH_ASSOC);

            $processedBookings[] = [
                'booking_id' => $booking['booking_id'],
                'tag_id' => $booking['tag_id'],
                'pet_name' => $booking['pet_name'],
                'breed' => $booking['breed'],
                'owner_name' => $booking['owner_name'],
                'status' => $booking['status'],
                'total_amount' => $booking['total_amount'],
                'check_in_time' => $booking['check_in_time'],
                'estimated_completion' => $booking['estimated_completion'],
                'actual_completion' => $booking['actual_completion'],
                'services' => $services,
                'status_history' => $statusHistory
            ];
        }

        echo json_encode([
            'success' => true,
            'data' => $processedBookings
        ]);
        exit;

    } catch (Exception $e) {
        error_log("Error loading user bookings: " . $e->getMessage());
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Error loading booking data'
        ]);
        exit;
    }
}

function handleSpecificRFIDTracking($rfid, $userEmail) {
    try {
        $db = getDB();
        
        // Get specific booking by RFID that belongs to the user
        $stmt = $db->prepare("
            SELECT 
                b.id as booking_id,
                b.custom_rfid as tag_id,
                b.status,
                b.total_amount,
                b.check_in_time,
                b.estimated_completion,
                b.actual_completion,
                p.name as pet_name,
                p.breed,
                c.name as owner_name,
                GROUP_CONCAT(CONCAT(s.name, '|', bs.price) SEPARATOR '|||') as services
            FROM bookings b
            JOIN pets p ON b.pet_id = p.id
            JOIN customers c ON p.customer_id = c.id
            LEFT JOIN booking_services bs ON b.id = bs.booking_id
            LEFT JOIN services s ON bs.service_id = s.id
            WHERE b.custom_rfid = ? AND c.email = ?
            AND b.status IN ('checked-in', 'bathing', 'grooming', 'ready')
            GROUP BY b.id
        ");
        $stmt->execute([$rfid, $userEmail]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$booking) {
            echo json_encode([
                'success' => false,
                'error' => 'RFID tag not found or no active booking'
            ]);
            exit;
        }

        $services = [];
        if ($booking['services']) {
            $serviceData = explode('|||', $booking['services']);
            foreach ($serviceData as $service) {
                $parts = explode('|', $service);
                if (count($parts) == 2) {
                    $services[] = [
                        'name' => $parts[0],
                        'price' => $parts[1]
                    ];
                }
            }
        }

        // Get status history
        $historyStmt = $db->prepare("
            SELECT status, created_at 
            FROM status_updates 
            WHERE booking_id = ? 
            ORDER BY created_at ASC
        ");
        $historyStmt->execute([$booking['booking_id']]);
        $statusHistory = $historyStmt->fetchAll(PDO::FETCH_ASSOC);

        $result = [
            'booking_id' => $booking['booking_id'],
            'tag_id' => $booking['tag_id'],
            'pet_name' => $booking['pet_name'],
            'breed' => $booking['breed'],
            'owner_name' => $booking['owner_name'],
            'status' => $booking['status'],
            'total_amount' => $booking['total_amount'],
            'check_in_time' => $booking['check_in_time'],
            'estimated_completion' => $booking['estimated_completion'],
            'actual_completion' => $booking['actual_completion'],
            'services' => $services,
            'status_history' => $statusHistory
        ];

        echo json_encode([
            'success' => true,
            'data' => $result
        ]);
        exit;

    } catch (Exception $e) {
        error_log("Error tracking RFID: " . $e->getMessage());
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => 'Error tracking pet'
        ]);
        exit;
    }
}

// JWT verification functions
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
?>