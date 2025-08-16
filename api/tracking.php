<?php
require_once '../config/database.php';

$method = $_SERVER['REQUEST_METHOD'];

switch($method) {
    case 'GET':
        if (isset($_GET['rfid'])) {
            trackByRFID($_GET['rfid']);
        } else {
            getActiveBookings();
        }
        break;
    case 'POST':
        updateStatus();
        break;
    default:
        http_response_code(405);
        echo json_encode(['error' => 'Method not allowed']);
        break;
}

function trackByRFID($rfidTag) {
    try {
        $db = getDB();
        
        $sql = "SELECT 
                    b.id as booking_id,
                    b.status,
                    b.total_amount,
                    b.check_in_time,
                    b.estimated_completion,
                    b.actual_completion,
                    p.name as pet_name,
                    p.breed,
                    p.age_range,
                    p.size,
                    c.name as owner_name,
                    c.phone as owner_phone,
                    c.email as owner_email,
                    rt.tag_id
                FROM bookings b
                JOIN pets p ON b.pet_id = p.id
                JOIN customers c ON p.customer_id = c.id
                JOIN rfid_tags rt ON b.rfid_tag_id = rt.id
                WHERE rt.tag_id = ? AND b.status NOT IN ('completed', 'cancelled')
                ORDER BY b.created_at DESC
                LIMIT 1";
        
        $stmt = $db->prepare($sql);
        $stmt->execute([$rfidTag]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$booking) {
            echo json_encode(['error' => 'No active booking found for this RFID tag']);
            return;
        }
        
        // Get services for this booking
        $stmt = $db->prepare("
            SELECT s.name, bs.price 
            FROM booking_services bs 
            JOIN services s ON bs.service_id = s.id 
            WHERE bs.booking_id = ?
        ");
        $stmt->execute([$booking['booking_id']]);
        $services = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        // Get status history
        $stmt = $db->prepare("
            SELECT status, notes, created_at 
            FROM status_updates 
            WHERE booking_id = ? 
            ORDER BY created_at ASC
        ");
        $stmt->execute([$booking['booking_id']]);
        $statusHistory = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        $booking['services'] = $services;
        $booking['status_history'] = $statusHistory;
        
        echo json_encode(['success' => true, 'data' => $booking]);
        
    } catch(Exception $e) {
        http_response_code(500);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function getActiveBookings() {
    try {
        $db = getDB();
        
        $sql = "SELECT 
                    b.id as booking_id,
                    b.status,
                    b.total_amount,
                    b.check_in_time,
                    b.estimated_completion,
                    p.name as pet_name,
                    p.breed,
                    c.name as owner_name,
                    c.phone as owner_phone,
                    rt.tag_id
                FROM bookings b
                JOIN pets p ON b.pet_id = p.id
                JOIN customers c ON p.customer_id = c.id
                JOIN rfid_tags rt ON b.rfid_tag_id = rt.id
                WHERE b.status NOT IN ('completed', 'cancelled')
                ORDER BY b.created_at DESC";
        
        $stmt = $db->prepare($sql);
        $stmt->execute();
        $bookings = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        echo json_encode(['success' => true, 'data' => $bookings]);
        
    } catch(Exception $e) {
        http_response_code(500);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function updateStatus() {
    try {
        $db = getDB();
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (!isset($input['booking_id']) || !isset($input['status'])) {
            throw new Exception('Booking ID and status are required');
        }
        
        $db->beginTransaction();
        
        // Update booking status
        $stmt = $db->prepare("UPDATE bookings SET status = ?, updated_at = NOW() WHERE id = ?");
        $stmt->execute([$input['status'], $input['booking_id']]);
        
        // Add status update record
        $notes = isset($input['notes']) ? $input['notes'] : '';
        $stmt = $db->prepare("INSERT INTO status_updates (booking_id, status, notes) VALUES (?, ?, ?)");
        $stmt->execute([$input['booking_id'], $input['status'], $notes]);
        
        // If status is completed, set actual completion time
        if ($input['status'] === 'completed') {
            $stmt = $db->prepare("UPDATE bookings SET actual_completion = NOW() WHERE id = ?");
            $stmt->execute([$input['booking_id']]);
        }
        
        $db->commit();
        
        echo json_encode(['success' => true, 'message' => 'Status updated successfully']);
        
    } catch(Exception $e) {
        if ($db->inTransaction()) {
            $db->rollback();
        }
        http_response_code(500);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

// RFID Scanner Integration Function (for when you get the device)
function handleRFIDScan() {
    try {
        // This function will be called when RFID device sends data
        // For now, it's a placeholder for future RFID device integration
        
        $db = getDB();
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (isset($input['rfid_tag'])) {
            // Log the RFID scan
            $stmt = $db->prepare("INSERT INTO rfid_scans (tag_id, scanned_at) VALUES (?, NOW())");
            $stmt->execute([$input['rfid_tag']]);
            
            // Return booking info for this tag
            trackByRFID($input['rfid_tag']);
        }
        
    } catch(Exception $e) {
        http_response_code(500);
        echo json_encode(['error' => $e->getMessage()]);
    }
}
?>