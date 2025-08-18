<?php
require_once '../config/database.php';
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

// Get tracking token from query parameter
$token = $_GET['token'] ?? '';

if (empty($token)) {
    echo json_encode([
        'success' => false,
        'message' => 'Tracking token is required'
    ]);
    exit;
}

try {
    $db = getDB();
    
    // Get booking data using custom_rfid as token
    $stmt = $db->prepare("
        SELECT 
            b.id as booking_id,
            b.status,
            b.total_amount,
            b.check_in_time,
            b.estimated_completion,
            b.actual_completion,
            b.staff_notes,
            b.custom_rfid,
            p.name as pet_name,
            p.type as pet_type,
            p.breed as pet_breed,
            p.age_range,
            p.size,
            p.special_notes,
            c.name as owner_name,
            c.phone as owner_phone,
            c.email as owner_email
        FROM bookings b
        JOIN pets p ON b.pet_id = p.id
        JOIN customers c ON p.customer_id = c.id
        WHERE b.custom_rfid = ?
        AND b.status != 'cancelled'
        ORDER BY b.created_at DESC
        LIMIT 1
    ");
    
    $stmt->execute([$token]);
    $booking = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$booking) {
        echo json_encode([
            'success' => false,
            'message' => 'No active booking found with this tracking ID. Please check your email link or contact our staff.'
        ]);
        exit;
    }
    
    // Get services for this booking
    $stmt = $db->prepare("
        SELECT s.name, s.description, bs.price
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
    
    // Prepare response data
    $responseData = [
        'booking_id' => $booking['booking_id'],
        'status' => $booking['status'],
        'total_amount' => $booking['total_amount'],
        'check_in_time' => $booking['check_in_time'],
        'estimated_completion' => $booking['estimated_completion'],
        'actual_completion' => $booking['actual_completion'],
        'staff_notes' => $booking['staff_notes'],
        'custom_rfid' => $booking['custom_rfid'],
        
        // Pet details
        'pet_name' => $booking['pet_name'],
        'pet_type' => ucfirst($booking['pet_type']),
        'pet_breed' => ucfirst($booking['pet_breed']),
        'age_range' => $booking['age_range'] ? ucfirst($booking['age_range']) : null,
        'size' => $booking['size'] ? ucfirst($booking['size']) : null,
        'special_notes' => $booking['special_notes'],
        
        // Owner details
        'owner_name' => $booking['owner_name'],
        'owner_phone' => $booking['owner_phone'],
        'owner_email' => $booking['owner_email'],
        
        // Services and history
        'services' => $services,
        'status_history' => $statusHistory
    ];
    
    echo json_encode([
        'success' => true,
        'data' => $responseData,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
    
} catch(Exception $e) {
    error_log('Guest dashboard error: ' . $e->getMessage());
    echo json_encode([
        'success' => false,
        'message' => 'An error occurred while loading your booking information. Please try again or contact our staff.',
        'error' => $e->getMessage()
    ]);
}
?>