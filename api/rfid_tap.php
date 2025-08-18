<?php
// Start output buffering FIRST
ob_start();

// Turn off error display to prevent HTML output
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

// Headers
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST');
header('Access-Control-Allow-Headers: Content-Type');

// Include your database connection file and email functions
require_once '../config/database.php';
require_once '../includes/email_functions.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    ob_clean();
    echo json_encode(['success' => false, 'message' => 'Method not allowed. Use POST.']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);

if (!$input || !isset($input['rfid_tag'])) {
    ob_clean();
    echo json_encode(['success' => false, 'message' => 'Invalid JSON or missing rfid_tag']);
    exit;
}

$rfidTag = trim($input['rfid_tag']);

if (empty($rfidTag)) {
    ob_clean();
    echo json_encode(['success' => false, 'message' => 'RFID tag cannot be empty']);
    exit;
}

try {
    $db = getDB();
    $db->beginTransaction();
    
    // Find RFID card and booking info
    $stmt = $db->prepare("
        SELECT 
            r.id as rfid_id,
            r.card_uid,
            r.custom_uid,
            r.tap_count,
            b.id as booking_id,
            p.name as pet_name,
            p.type as pet_type,
            p.breed as pet_breed,
            c.name as owner_name,
            c.email as owner_email,
            c.phone as owner_phone
        FROM rfid_cards r
        LEFT JOIN bookings b ON r.id = b.rfid_tag_id
        LEFT JOIN pets p ON b.pet_id = p.id
        LEFT JOIN customers c ON p.customer_id = c.id
        WHERE r.card_uid = ? OR r.custom_uid = ?
        LIMIT 1
    ");
    $stmt->execute([$rfidTag, $rfidTag]);
    $rfidData = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$rfidData) {
        $db->rollBack();
        ob_clean();
        echo json_encode([
            'success' => false, 
            'message' => 'RFID tag not found: ' . $rfidTag
        ]);
        exit;
    }
    
    // Update tap count
    $newTapCount = (int)$rfidData['tap_count'] + 1;
    $stmt = $db->prepare("UPDATE rfid_cards SET tap_count = ? WHERE id = ?");
    $stmt->execute([$newTapCount, $rfidData['rfid_id']]);
    
    // Get status
    $status = getStatusFromTapCount($newTapCount);
    
    $db->commit();
    
    // Send email automatically
    $emailSent = false;
    $emailError = null;
    
    if ($rfidData['booking_id'] && $rfidData['owner_email']) {
        try {
            $emailSent = sendBookingStatusEmail($rfidData['booking_id']);
            if (!$emailSent) {
                $emailError = "Email sending failed - check SMTP configuration";
            }
        } catch (Exception $e) {
            $emailError = "Email error: " . $e->getMessage();
        }
    } else {
        $emailError = $rfidData['booking_id'] ? "No owner email found" : "No booking found";
    }
    
    // Clear any buffered output and send clean JSON
    ob_clean();
    
    // Success response
    echo json_encode([
        'success' => true,
        'message' => 'RFID tap processed successfully! 🎉',
        'data' => [
            'rfid_tag' => $rfidData['custom_uid'] ?: $rfidData['card_uid'],
            'pet_name' => $rfidData['pet_name'],
            'pet_type' => $rfidData['pet_type'],
            'pet_breed' => $rfidData['pet_breed'],
            'owner_name' => $rfidData['owner_name'],
            'owner_email' => $rfidData['owner_email'],
            'previous_tap_count' => (int)$rfidData['tap_count'],
            'new_tap_count' => $newTapCount,
            'status' => $status,
            'status_emoji' => getStatusEmoji($status),
            'booking_id' => $rfidData['booking_id'],
            'email_sent' => $emailSent,
            'email_error' => $emailError
        ]
    ], JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    if (isset($db)) {
        $db->rollBack();
    }
    
    // Log the error
    error_log("RFID Tap Error: " . $e->getMessage() . " in " . $e->getFile() . " line " . $e->getLine());
    
    // Clear any buffered output and send clean error JSON
    ob_clean();
    
    echo json_encode([
        'success' => false,
        'message' => 'Error: ' . $e->getMessage(),
        'debug_info' => [
            'file' => basename($e->getFile()),
            'line' => $e->getLine()
        ]
    ]);
}

function getStatusEmoji($status) {
    $emojis = [
        'unknown' => '❓',
        'checked-in' => '✅', 
        'bathing' => '🛁',
        'grooming' => '✂️',
        'ready for pickup' => '🎉'
    ];
    return $emojis[$status] ?? '📋';
}

// End output buffering
ob_end_flush();
?>