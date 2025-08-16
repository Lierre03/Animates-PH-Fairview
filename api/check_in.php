<?php
require_once '../config/database.php';

$method = $_SERVER['REQUEST_METHOD'];

switch($method) {
    case 'POST':
        handleCheckin();
        break;
    default:
        http_response_code(405);
        echo json_encode(['error' => 'Method not allowed']);
        break;
}

function handleCheckin() {
    try {
        $db = getDB();
        $input = json_decode(file_get_contents('php://input'), true);
        
        // Validate required fields
        $required = ['petName', 'petType', 'petBreed', 'ownerName', 'ownerPhone', 'ownerEmail'];
        foreach ($required as $field) {
            if (empty($input[$field])) {
                throw new Exception("Missing required field: $field");
            }
        }
        
        // Start transaction
        $db->beginTransaction();
        
        // 1. Insert or find customer
        $customerId = findOrCreateCustomer($db, $input);
        
        // 2. Insert pet
        $petId = createPet($db, $customerId, $input);
        
        // 3. Assign RFID tag
        $rfidTagId = assignRFIDTag($db, $petId);
        
        // 4. Create booking
        $bookingId = createBooking($db, $petId, $rfidTagId, $input);
        
        // 5. Add services to booking
        addServicesToBooking($db, $bookingId, $input['services']);
        
        // 6. Create initial status update
        createStatusUpdate($db, $bookingId, 'checked-in', 'Pet checked in successfully');
        
        // Commit transaction
        $db->commit();
        
        // Get the assigned RFID tag
        $stmt = $db->prepare("SELECT tag_id FROM rfid_tags WHERE id = ?");
        $stmt->execute([$rfidTagId]);
        $rfidTag = $stmt->fetch(PDO::FETCH_ASSOC);
        
        echo json_encode([
            'success' => true,
            'booking_id' => $bookingId,
            'rfid_tag' => $rfidTag['tag_id'],
            'message' => 'Check-in completed successfully'
        ]);
        
    } catch(Exception $e) {
        if ($db->inTransaction()) {
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
        $stmt = $db->prepare("UPDATE customers SET name = ?, email = ? WHERE id = ?");
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
    // Map age values to database format
    $ageRange = null;
    if (!empty($input['petAge'])) {
        $validAges = ['puppy', 'young', 'adult', 'senior']; // adjust based on your database
        if (in_array(strtolower($input['petAge']), $validAges)) {
            $ageRange = $input['petAge'];
        }
    }
    
    $stmt = $db->prepare("INSERT INTO pets (customer_id, name, type, pet_type, breed, age_range, size, special_notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([
        $customerId,
        $input['petName'],
        $input['petType'],
        $input['petType'],
        $input['petBreed'],
        $ageRange,
        $input['petSize'],
        $input['specialNotes']
    ]);
    return $db->lastInsertId();
}
function assignRFIDTag($db, $petId) {
    // Find an available RFID tag
    $stmt = $db->prepare("SELECT id, tag_id FROM rfid_tags WHERE pet_id IS NULL AND is_active = 1 LIMIT 1");
    $stmt->execute();
    $tag = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if (!$tag) {
        throw new Exception('No available RFID tags');
    }
    
    // Assign the tag to the pet
    $stmt = $db->prepare("UPDATE rfid_tags SET pet_id = ?, assigned_at = NOW() WHERE id = ?");
    $stmt->execute([$petId, $tag['id']]);
    
    return $tag['id'];
}

function createBooking($db, $petId, $rfidTagId, $input) {
    $stmt = $db->prepare("INSERT INTO bookings (pet_id, rfid_tag_id, total_amount, estimated_completion) VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL 2 HOUR))");
    $stmt->execute([$petId, $rfidTagId, $input['totalAmount']]);
    return $db->lastInsertId();
}

function addServicesToBooking($db, $bookingId, $services) {
    foreach ($services as $service) {
        // Get service ID by name
        $stmt = $db->prepare("SELECT id, price FROM services WHERE name = ?");
        $stmt->execute([$service['name']]);
        $serviceData = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($serviceData) {
            $stmt = $db->prepare("INSERT INTO booking_services (booking_id, service_id, price) VALUES (?, ?, ?)");
            $stmt->execute([$bookingId, $serviceData['id'], $service['price']]);
        }
    }
}

function createStatusUpdate($db, $bookingId, $status, $notes) {
    $stmt = $db->prepare("INSERT INTO status_updates (booking_id, status, notes) VALUES (?, ?, ?)");
    $stmt->execute([$bookingId, $status, $notes]);
}
?>