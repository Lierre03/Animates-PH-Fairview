<?php
require_once '../config/database.php';
require_once '../includes/email_functions.php';

// This script should be called whenever an RFID tap occurs
// It updates the status based on tap_count and sends email notifications

$method = $_SERVER['REQUEST_METHOD'];

switch($method) {
    case 'POST':
        handleRFIDStatusUpdate();
        break;
    case 'GET':
        // Allow GET requests for testing
        if (isset($_GET['custom_uid'])) {
            $_POST['custom_uid'] = $_GET['custom_uid'];
            handleRFIDStatusUpdate();
        } else {
            http_response_code(400);
            echo json_encode(['error' => 'Missing custom_uid parameter']);
        }
        break;
    default:
        http_response_code(405);
        echo json_encode(['error' => 'Method not allowed']);
        break;
}

function handleRFIDStatusUpdate() {
    try {
        $db = getDB();
        
        // Get input data
        $input = null;
        if ($_SERVER['REQUEST_METHOD'] === 'POST') {
            $rawInput = file_get_contents('php://input');
            if (!empty($rawInput)) {
                $input = json_decode($rawInput, true);
            } else {
                $input = $_POST;
            }
        } else {
            $input = $_GET;
        }
        
        // Validate required fields
        if (empty($input['custom_uid'])) {
            throw new Exception("Missing RFID custom_uid");
        }
        
        $customUid = $input['custom_uid'];
        
        error_log("Checking RFID status update for: $customUid");
        
        // Get the current tap count from rfid_cards
        $stmt = $db->prepare("SELECT id, tap_count, updated_at FROM rfid_cards WHERE custom_uid = ?");
        $stmt->execute([$customUid]);
        $rfidCard = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$rfidCard) {
            throw new Exception("RFID card not found: $customUid");
        }
        
        // Find the booking using this RFID
        $stmt = $db->prepare("
            SELECT b.id, b.status as booking_status, p.name as pet_name, c.name as owner_name
            FROM bookings b
            JOIN pets p ON b.pet_id = p.id
            JOIN customers c ON p.customer_id = c.id
            WHERE b.custom_rfid = ? 
            AND b.status NOT IN ('completed', 'cancelled')
        ");
        $stmt->execute([$customUid]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$booking) {
            throw new Exception("Active booking not found for RFID: $customUid");
        }
        
        $bookingId = $booking['id'];
        $tapCount = $rfidCard['tap_count'];
        
        // Check if we already processed this tap count for this booking
        $stmt = $db->prepare("
            SELECT COUNT(*) as count 
            FROM status_updates 
            WHERE booking_id = ? 
            AND notes LIKE ?
        ");
        $tapCountCheck = "tap count: {$tapCount}%";
        $stmt->execute([$bookingId, $tapCountCheck]);
        $existingUpdate = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($existingUpdate['count'] > 0) {
            // Already processed this tap count, no update needed
            error_log("Tap count $tapCount already processed for booking $bookingId");
            throw new Exception("Status already updated for this tap count");
        }
        
        // Determine status based on tap count
        $status = getStatusFromTapCount($tapCount);
        $notes = "Status updated via RFID tap (tap count: {$tapCount}) at " . date('Y-m-d H:i:s');
        
        error_log("Updating booking $bookingId to status: $status (tap count: $tapCount)");
        
        // Start transaction
        $db->beginTransaction();
        
        // Update status_updates table
        $stmt = $db->prepare("INSERT INTO status_updates (booking_id, status, notes, created_at) VALUES (?, ?, ?, NOW())");
        $stmt->execute([$bookingId, $status, $notes]);
        
        // Update booking status
        $stmt = $db->prepare("UPDATE bookings SET status = ?, updated_at = NOW() WHERE id = ?");
        $stmt->execute([$status, $bookingId]);
        
        // Commit transaction
        $db->commit();
        
        // Send email notification (outside transaction to avoid rollback issues)
        $emailSent = false;
        try {
            $emailSent = sendBookingStatusEmail($bookingId);
            error_log("Email notification result: " . ($emailSent ? 'SUCCESS' : 'FAILED'));
        } catch (Exception $e) {
            error_log("Email notification failed: " . $e->getMessage());
            // Don't fail the status update if email fails
        }
        
        echo json_encode([
            'success' => true,
            'booking_id' => $bookingId,
            'pet_name' => $booking['pet_name'],
            'owner_name' => $booking['owner_name'],
            'status' => $status,
            'tap_count' => $tapCount,
            'email_sent' => $emailSent,
            'message' => "Status updated to {$status}",
            'rfid_updated_at' => $rfidCard['updated_at']
        ]);
        
    } catch(Exception $e) {
        if (isset($db) && $db->inTransaction()) {
            $db->rollback();
        }
        
        error_log("RFID status update error: " . $e->getMessage());
        
        // Return appropriate HTTP status codes
        if (strpos($e->getMessage(), 'not found') !== false) {
            http_response_code(404);
        } elseif (strpos($e->getMessage(), 'already updated') !== false || strpos($e->getMessage(), 'already processed') !== false) {
            http_response_code(204); // No Content - no update needed
        } else {
            http_response_code(500);
        }
        
        echo json_encode([
            'error' => $e->getMessage(),
            'custom_uid' => $customUid ?? null
        ]);
    }
}
?>