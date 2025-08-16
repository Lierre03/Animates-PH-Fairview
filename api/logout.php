<?php
// Always return JSON
header('Content-Type: application/json');

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

if ($method === 'POST') {
    handleLogout();
} else {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

function handleLogout() {
    try {
        $token = getBearerToken();
        
        if ($token) {
            // Verify and decode the token to get user info
            $decoded = verifyJWT($token);
            $db = getDB();
            
            // Update last_logout timestamp in database
            $stmt = $db->prepare("UPDATE users SET last_logout = NOW() WHERE id = ?");
            $stmt->execute([$decoded->user_id]);
            
            // In a production environment, you might want to blacklist the token
            // For now, we'll just rely on client-side token removal
            
            echo json_encode([
                'success' => true,
                'message' => 'Logged out successfully'
            ]);
        } else {
            // No token provided, but still consider it a successful logout
            echo json_encode([
                'success' => true,
                'message' => 'Already logged out'
            ]);
        }
        exit;
        
    } catch(Exception $e) {
        // Even if token verification fails, consider logout successful
        echo json_encode([
            'success' => true,
            'message' => 'Logged out successfully'
        ]);
        exit;
    }
}

// JWT verification functions (copied from auth.php for consistency)
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