<?php
require_once '../config/database.php';

// Set headers for API
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

try {
    $db = getDB();
    $input = json_decode(file_get_contents('php://input'), true);
    
    if (!$input) {
        throw new Exception('Invalid JSON data');
    }
    
    // Start transaction
    $db->beginTransaction();
    
    // 1. Insert/Update RFID card record
    $cardId = handleRFIDCard($db, $input);
    
    // 2. Insert tap history
    insertTapHistory($db, $cardId, $input);
    
    // Commit transaction
    $db->commit();
    
    echo json_encode([
        'success' => true,
        'card_id' => $cardId,
        'custom_uid' => $input['custom_uid'],
        'tap_count' => $input['tap_count'],
        'message' => 'RFID data saved successfully'
    ]);
    
} catch(Exception $e) {
    if ($db->inTransaction()) {
        $db->rollback();
    }
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
}

function handleRFIDCard($db, $input) {
    // Check if card exists
    $stmt = $db->prepare("SELECT id, tap_count FROM rfid_cards WHERE card_uid = ?");
    $stmt->execute([$input['card_uid']]);
    $existingCard = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($existingCard) {
        // Update existing card
        $stmt = $db->prepare("
            UPDATE rfid_cards 
            SET custom_uid = ?, tap_count = ?, updated_at = NOW(), 
                last_firebase_sync = NOW(), device_source = ?
            WHERE card_uid = ?
        ");
        $stmt->execute([
            $input['custom_uid'],
            $input['tap_count'],
            $input['device_info'],
            $input['card_uid']
        ]);
        
        return $existingCard['id'];
    } else {
        // Insert new card
        $stmt = $db->prepare("
            INSERT INTO rfid_cards 
            (card_uid, custom_uid, tap_count, max_taps, device_source, status) 
            VALUES (?, ?, ?, ?, ?, 'active')
        ");
        $stmt->execute([
            $input['card_uid'],
            $input['custom_uid'],
            $input['tap_count'],
            $input['max_taps'],
            $input['device_info']
        ]);
        
        return $db->lastInsertId();
    }
}

function insertTapHistory($db, $cardId, $input) {
    $stmt = $db->prepare("
        INSERT INTO rfid_tap_history 
        (rfid_card_id, card_uid, custom_uid, tap_number, tapped_at, 
         device_info, wifi_network, signal_strength, validation_status, 
         readable_time, timestamp_value, rfid_scanner_status) 
        VALUES (?, ?, ?, ?, NOW(), ?, ?, ?, ?, ?, ?, ?)
    ");
    
    $stmt->execute([
        $cardId,
        $input['card_uid'],
        $input['custom_uid'],
        $input['tap_number'],
        $input['device_info'],
        $input['wifi_network'] ?? null,
        $input['signal_strength'] ?? null,
        $input['validation_status'],
        $input['readable_time'],
        $input['timestamp_value'],
        $input['rfid_scanner_status']
    ]);
}
?>