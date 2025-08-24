<?php
require_once '../config/database.php';
require_once '../includes/email_functions.php'; // Add this line

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

// UPDATED main endpoint logic to handle completion email
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
    
    // 3. Update booking status based on tap count
    $bookingResult = updateBookingStatus($db, $cardId, $input);
    
    // Commit transaction before sending email
    $db->commit();
    
    // 4. Send email notification based on booking status
    $emailSent = false;
    if ($bookingResult['updated'] && $bookingResult['booking_id']) {
        try {
            // Check if this is completion (tap 5)
            if ($bookingResult['is_completion']) {
                // Send completion/pickup email - NEW
                $emailSent = sendCompletionEmail($bookingResult['booking_id']);
            } else {
                // Send regular status update email
                $emailSent = sendBookingStatusEmail($bookingResult['booking_id']);
            }
        } catch (Exception $emailError) {
            error_log("Email sending failed for booking {$bookingResult['booking_id']}: " . $emailError->getMessage());
            // Don't fail the API call if email fails
        }
    }
    
    echo json_encode([
        'success' => true,
        'card_id' => $cardId,
        'custom_uid' => $input['custom_uid'],
        'tap_count' => $input['tap_count'],
        'booking_updated' => $bookingResult['updated'],
        'booking_id' => $bookingResult['booking_id'],
        'status_changed_to' => $bookingResult['new_status'],
        'is_completion' => $bookingResult['is_completion'],
        'email_sent' => $emailSent,
        'message' => 'RFID data saved successfully' . 
                    ($bookingResult['updated'] ? ' and booking status updated' : '') .
                    ($emailSent ? ' and email notification sent' : '') .
                    ($bookingResult['is_completion'] ? ' - Service completed!' : '')
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


function updateBookingStatus($db, $cardId, $input) {
    $tapCount = $input['tap_count'];
    $customUID = $input['custom_uid'];
    
    // UPDATED status mapping to include tap 5 for completion
    $statusMap = [
        1 => 'checked-in',
        2 => 'bathing', 
        3 => 'grooming',
        4 => 'ready',
        5 => 'completed'  // NEW - tap 5 completes the service
    ];
    
    // Return result structure
    $result = [
        'updated' => false,
        'booking_id' => null,
        'new_status' => null,
        'is_completion' => false  // NEW - track if this is completion tap
    ];
    
    // Skip if tap count is not in our mapping
    if (!isset($statusMap[$tapCount])) {
        return $result;
    }
    
    $newStatus = $statusMap[$tapCount];
    $result['is_completion'] = ($tapCount === 5);  // NEW - check if completion
    
    // Find booking using custom_rfid (which matches custom_uid)
    // In updateBookingStatus(), change the query to:
    $stmt = $db->prepare("
        SELECT b.id, b.status, b.custom_rfid
        FROM bookings b
        JOIN rfid_cards r ON r.id = b.rfid_card_id 
        WHERE r.card_uid = ? 
        AND b.status NOT IN ('completed', 'cancelled')
        ORDER BY b.created_at DESC 
        LIMIT 1
    ");
    $stmt->execute([$input['card_uid']]); // Use card_uid instead of custom_uid
    $booking = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$booking) {
        // No active booking found for this custom UID
        return $result;
    }
    
    // Check if status actually needs updating
    if ($booking['status'] === $newStatus) {
        return $result;
    }
    
    // Update booking status
    $stmt = $db->prepare("
        UPDATE bookings 
        SET status = ?, updated_at = NOW()
        WHERE id = ?
    ");
    $stmt->execute([$newStatus, $booking['id']]);
    
    // Add status update record
    $stmt = $db->prepare("
        INSERT INTO status_updates (booking_id, status, notes, updated_by, created_at) 
        VALUES (?, ?, ?, ?, NOW())
    ");
    
    $notes = "Status automatically updated via RFID tap #" . $tapCount;
    if ($tapCount === 5) {
        $notes = "Service completed! Pet picked up via RFID tap #" . $tapCount;
    }
    
    $stmt->execute([
        $booking['id'],
        $newStatus,
        $notes,
        "RFID System"
    ]);
    
    // If status is 'ready', update actual_completion time (tap 4)
    if ($newStatus === 'ready') {
        $stmt = $db->prepare("
            UPDATE bookings 
            SET actual_completion = NOW() 
            WHERE id = ?
        ");
        $stmt->execute([$booking['id']]);
    }
    
    // If status is 'completed', update pickup time (tap 5) - NEW
    if ($newStatus === 'completed') {
        $stmt = $db->prepare("
            UPDATE bookings 
            SET actual_completion = NOW()
            WHERE id = ?
        ");
        $stmt->execute([$booking['id']]);
    }
    
    // Update result
    $result['updated'] = true;
    $result['booking_id'] = $booking['id'];
    $result['new_status'] = $newStatus;
    
    return $result;
}

?>