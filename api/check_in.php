<?php
require_once '../config/database.php';

$method = $_SERVER['REQUEST_METHOD'];

switch($method) {
    case 'POST':
        handleCheckin();
        break;
    case 'GET':
        if (isset($_GET['action']) && $_GET['action'] === 'get_latest_rfid') {
            getLatestRFIDFromMySQL();
        }
        break;
    default:
        http_response_code(405);
        echo json_encode(['error' => 'Method not allowed']);
        break;
}

function getLatestRFIDFromMySQL() {
    try {
        $db = getDB();
        
        // Get latest RFID tap from tap_history
        $stmt = $db->prepare("
            SELECT rth.*, rc.custom_uid, rc.tap_count as card_tap_count,
                   rc.status as card_status, rc.id as card_id
            FROM rfid_tap_history rth
            JOIN rfid_cards rc ON rc.id = rth.rfid_card_id
            WHERE rc.status = 'active'
            ORDER BY rth.tapped_at DESC
            LIMIT 1
        ");
        $stmt->execute();
        $latestTap = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$latestTap) {
            echo json_encode([
                'success' => false, 
                'message' => 'No RFID data found'
            ]);
            return;
        }
        
        // Check if this is a first tap (tap_number = 1) or subsequent tap
        if ($latestTap['tap_number'] == 1) {
            // Check if RFID card is available for new booking
            $isAvailable = isRFIDAvailableForBooking($db, $latestTap['custom_uid'], $latestTap['card_id']);
            
            if ($isAvailable) {
                // First tap and available - ready for check-in
                echo json_encode([
                    'success' => true,
                    'customUID' => $latestTap['custom_uid'],
                    'cardUID' => $latestTap['card_uid'],
                    'cardId' => $latestTap['card_id'],
                    'tapCount' => $latestTap['tap_number'],
                    'isFirstTap' => true,
                    'message' => 'RFID card detected and ready for check-in',
                    'timestamp' => $latestTap['tapped_at']
                ]);
            } else {
                // RFID is in use by active booking
                echo json_encode([
                    'success' => false,
                    'message' => 'RFID card is currently in use by another booking'
                ]);
            }
        } else {
            // Subsequent tap - update pet status if booking exists
            updatePetStatusByRFID($latestTap['custom_uid']);
            
            echo json_encode([
                'success' => true,
                'customUID' => $latestTap['custom_uid'],
                'cardUID' => $latestTap['card_uid'],
                'tapCount' => $latestTap['tap_number'],
                'isFirstTap' => false,
                'message' => 'RFID tap logged - Status updated',
                'timestamp' => $latestTap['tapped_at']
            ]);
        }
        
    } catch(Exception $e) {
        error_log('MySQL RFID polling error: ' . $e->getMessage());
        echo json_encode(['success' => false, 'error' => $e->getMessage()]);
    }
}

function isRFIDAvailableForBooking($db, $customUID, $cardId) {
    // Check if RFID card is being used in any active booking
    $stmt = $db->prepare("
        SELECT COUNT(*) as count 
        FROM bookings 
        WHERE (custom_rfid = ? OR rfid_card_id = ?) 
        AND status NOT IN ('completed', 'cancelled')
    ");
    $stmt->execute([$customUID, $cardId]);
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    
    return $result['count'] == 0;
}

function updatePetStatusByRFID($customUID) {
    try {
        $db = getDB();
        
        // Find active booking by custom_uid or rfid_card_id
        $stmt = $db->prepare("
            SELECT b.id, b.status, b.rfid_card_id
            FROM bookings b 
            WHERE b.custom_rfid = ? 
            AND b.status NOT IN ('completed', 'cancelled')
            ORDER BY b.created_at DESC 
            LIMIT 1
        ");
        $stmt->execute([$customUID]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($booking) {
            // Update status based on current status
            $newStatus = getNextStatus($booking['status']);
            if ($newStatus) {
                $stmt = $db->prepare("UPDATE bookings SET status = ?, updated_at = NOW() WHERE id = ?");
                $stmt->execute([$newStatus, $booking['id']]);
                
                // Create status update log
                $stmt = $db->prepare("INSERT INTO status_updates (booking_id, status, notes) VALUES (?, ?, ?)");
                $stmt->execute([$booking['id'], $newStatus, "Status updated via RFID tap"]);
                
                // If booking is completed, the RFID card becomes available again
                if ($newStatus === 'completed') {
                    error_log("Booking completed: RFID {$customUID} is now available for reuse");
                }
                
                error_log("Pet status updated: Booking ID {$booking['id']} -> {$newStatus}");
            }
        } else {
            error_log("No active booking found for RFID: {$customUID}");
        }
    } catch(Exception $e) {
        error_log('Status update error: ' . $e->getMessage());
    }
}

function getNextStatus($currentStatus) {
    $statusFlow = [
        'checked-in' => 'bathing',
        'bathing' => 'grooming', 
        'grooming' => 'ready',
        'ready' => 'completed'
    ];
    
    return $statusFlow[$currentStatus] ?? null;
}

function handleCheckin() {
    try {
        $db = getDB();
        $input = json_decode(file_get_contents('php://input'), true);
        
        // Validate required fields
        $required = ['petName', 'petType', 'petBreed', 'ownerName', 'ownerPhone', 'ownerEmail', 'customRFID'];
        foreach ($required as $field) {
            if (empty($input[$field])) {
                throw new Exception("Missing required field: $field");
            }
        }
        
        // Validate that RFID exists and get card details
        $stmt = $db->prepare("SELECT id FROM rfid_cards WHERE custom_uid = ? AND status = 'active'");
        $stmt->execute([$input['customRFID']]);
        $rfidCard = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$rfidCard) {
            throw new Exception("RFID card not found or inactive: " . $input['customRFID']);
        }
        
        // Check if RFID is available for new booking
        if (!isRFIDAvailableForBooking($db, $input['customRFID'], $rfidCard['id'])) {
            throw new Exception("RFID card is currently in use by another active booking");
        }
        
        // Start transaction
        $db->beginTransaction();
        
        // 1. Insert or find customer
        $customerId = findOrCreateCustomer($db, $input);
        
        // 2. Insert pet
        $petId = createPet($db, $customerId, $input);
        
        // 3. Create booking with custom RFID and card ID
        $bookingId = createBooking($db, $petId, $rfidCard['id'], $input);
        
        // 4. Add services to booking
        addServicesToBooking($db, $bookingId, $input['services']);
        
        // 5. Create initial status update
        createStatusUpdate($db, $bookingId, 'checked-in', 'Pet checked in successfully');
        
        // Commit transaction
        $db->commit();
        
        echo json_encode([
            'success' => true,
            'booking_id' => $bookingId,
            'rfid_tag' => $input['customRFID'],
            'message' => 'Check-in completed successfully'
        ]);
        
    } catch(Exception $e) {
        if ($db && $db->inTransaction()) {
            $db->rollback();
        }
        http_response_code(500);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function findOrCreateCustomer($db, $input) {
    // Check if customer exists by phone
    $stmt = $db->prepare("SELECT id FROM customers WHERE phone = ?");
    $stmt->execute([$input['ownerPhone']]);
    $customer = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($customer) {
        // Update customer info
        $stmt = $db->prepare("UPDATE customers SET name = ?, email = ?, updated_at = NOW() WHERE id = ?");
        $stmt->execute([$input['ownerName'], $input['ownerEmail'], $customer['id']]);
        return $customer['id'];
    } else {
        // Create new customer
        $stmt = $db->prepare("INSERT INTO customers (name, phone, email) VALUES (?, ?, ?)");
        $stmt->execute([$input['ownerName'], $input['ownerPhone'], $input['ownerEmail']]);
        return $db->lastInsertId();
    }
}

function createPet($db, $customerId, $input) {
    // Handle age range mapping and validation
    $ageRange = null;
    if (!empty($input['petAge'])) {
        // Map common age descriptions to valid enum values
        $ageMapping = [
            'puppy' => 'puppy',
            'young' => 'young', 
            'adult' => 'adult',
            'senior' => 'senior',
            'kitten' => 'puppy',  // Map kitten to puppy (both are babies)
            'baby' => 'puppy',
            'juvenile' => 'young',
            'old' => 'senior',
            'elderly' => 'senior'
        ];
        
        $inputAge = strtolower(trim($input['petAge']));
        if (isset($ageMapping[$inputAge])) {
            $ageRange = $ageMapping[$inputAge];
        }
        // If age is not recognized, leave as null rather than cause error
    }
    
    // Handle pet size validation
    $petSize = null;
    if (!empty($input['petSize'])) {
        $validSizes = ['small', 'medium', 'large', 'extra_large'];
        $inputSize = strtolower(trim($input['petSize']));
        if (in_array($inputSize, $validSizes)) {
            $petSize = $inputSize;
        }
    }
    
    $stmt = $db->prepare("
        INSERT INTO pets (customer_id, name, type, pet_type, breed, age_range, size, special_notes) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ");
    $stmt->execute([
        $customerId,
        $input['petName'],
        $input['petType'],
        $input['petType'],
        $input['petBreed'],
        $ageRange,
        $petSize,
        $input['specialNotes'] ?? null
    ]);
    return $db->lastInsertId();
}

function createBooking($db, $petId, $rfidCardId, $input) {
    $stmt = $db->prepare("
        INSERT INTO bookings (pet_id, rfid_card_id, custom_rfid, total_amount, estimated_completion) 
        VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 2 HOUR))
    ");
    $stmt->execute([$petId, $rfidCardId, $input['customRFID'], $input['totalAmount'] ?? 0]);
    return $db->lastInsertId();
}

function addServicesToBooking($db, $bookingId, $services) {
    if (!empty($services) && is_array($services)) {
        foreach ($services as $service) {
            // Get service ID by name
            $stmt = $db->prepare("SELECT id, price FROM services WHERE name = ?");
            $stmt->execute([$service['name']]);
            $serviceData = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if ($serviceData) {
                $stmt = $db->prepare("INSERT INTO booking_services (booking_id, service_id, price) VALUES (?, ?, ?)");
                $stmt->execute([$bookingId, $serviceData['id'], $service['price'] ?? $serviceData['price']]);
            } else {
                // Create service if it doesn't exist
                $stmt = $db->prepare("INSERT INTO services (name, description, price) VALUES (?, ?, ?)");
                $stmt->execute([$service['name'], $service['name'], $service['price']]);
                $newServiceId = $db->lastInsertId();
                
                $stmt = $db->prepare("INSERT INTO booking_services (booking_id, service_id, price) VALUES (?, ?, ?)");
                $stmt->execute([$bookingId, $newServiceId, $service['price']]);
            }
        }
    }
}

function createStatusUpdate($db, $bookingId, $status, $notes) {
    $stmt = $db->prepare("INSERT INTO status_updates (booking_id, status, notes) VALUES (?, ?, ?)");
    $stmt->execute([$bookingId, $status, $notes]);
}
?>