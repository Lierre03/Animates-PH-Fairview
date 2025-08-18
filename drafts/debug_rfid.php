<?php
// Catch ALL output and errors
ob_start();
error_reporting(E_ALL);
ini_set('display_errors', 0);

try {
    // Headers first
    header('Content-Type: application/json');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: POST');
    header('Access-Control-Allow-Headers: Content-Type');
    
    // Try to include database
    require_once '../config/database.php';
    
    // Check request method
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        throw new Exception('Method not allowed. Use POST.');
    }
    
    // Get input
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input || !isset($input['rfid_tag'])) {
        throw new Exception('Invalid JSON or missing rfid_tag');
    }
    
    $rfidTag = trim($input['rfid_tag']);
    if (empty($rfidTag)) {
        throw new Exception('RFID tag cannot be empty');
    }
    
    // Test database connection
    if (!function_exists('getDB')) {
        throw new Exception('getDB() function not found in database.php');
    }
    
    $db = getDB();
    if (!$db) {
        throw new Exception('Database connection failed');
    }
    
    // Simple query test
    $stmt = $db->prepare("SELECT id, card_uid, custom_uid, tap_count FROM rfid_cards WHERE card_uid = ? OR custom_uid = ? LIMIT 1");
    $stmt->execute([$rfidTag, $rfidTag]);
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    
    // Clear any buffered output
    ob_clean();
    
    // Return success response
    echo json_encode([
        'success' => true,
        'message' => 'RFID test successful',
        'data' => [
            'rfid_tag' => $rfidTag,
            'found_in_db' => $result ? true : false,
            'db_data' => $result,
            'functions_available' => [
                'getDB' => function_exists('getDB'),
                'getStatusFromTapCount' => function_exists('getStatusFromTapCount'),
                'sendBookingStatusEmail' => function_exists('sendBookingStatusEmail')
            ]
        ]
    ], JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    // Clear any output
    ob_clean();
    
    // Return error as JSON
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage(),
        'file' => basename($e->getFile()),
        'line' => $e->getLine()
    ], JSON_PRETTY_PRINT);
} catch (Error $e) {
    // Catch fatal errors too
    ob_clean();
    echo json_encode([
        'success' => false,
        'message' => 'PHP Error: ' . $e->getMessage(),
        'file' => basename($e->getFile()),
        'line' => $e->getLine()
    ], JSON_PRETTY_PRINT);
}

// End output buffering
ob_end_flush();
?>