<?php
require_once '../config/database.php';

$method = $_SERVER['REQUEST_METHOD'];

if ($method !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

try {
    $db = getDB();
    $input = json_decode(file_get_contents('php://input'), true);
    
    $today = $input['date'] ?? date('Y-m-d');
    
    // Find the latest RFID card with tap_count = 1 and today's date
    $stmt = $db->prepare("
        SELECT id, custom_uid, updated_at 
        FROM rfid_cards 
        WHERE tap_count = 1 
        AND DATE(updated_at) = ? 
        AND is_active = 1 
        ORDER BY updated_at DESC 
        LIMIT 1
    ");
    $stmt->execute([$today]);
    $card = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($card) {
        echo json_encode([
            'success' => true,
            'custom_uid' => $card['custom_uid'],
            'id' => $card['id'],
            'updated_at' => $card['updated_at']
        ]);
    } else {
        echo json_encode([
            'success' => false,
            'error' => 'No RFID card found for today with tap_count = 1'
        ]);
    }
    
} catch(Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
}
?>