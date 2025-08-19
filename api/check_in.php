<?php
require_once '../config/database.php';
require_once '../includes/email_functions.php';


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
        // Add a small delay to prevent rapid successive requests
        $lockFile = sys_get_temp_dir() . '/booking_lock_' . md5($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        
        if (file_exists($lockFile) && (time() - filemtime($lockFile)) < 5) {
            http_response_code(429);
            echo json_encode(['error' => 'Please wait before creating another booking']);
            return;
        }
        
        // Create lock file
        file_put_contents($lockFile, time());
        
        $db = getDB();
        $input = json_decode(file_get_contents('php://input'), true);
        
        // Validate required fields
        $required = ['petName', 'petType', 'petBreed', 'ownerName', 'ownerPhone', 'ownerEmail', 'customRFID'];
        foreach ($required as $field) {
            if (empty($input[$field])) {
                throw new Exception("Missing required field: $field");
            }
        }
        
        // Begin transaction
        $db->beginTransaction();
        
        // Find RFID card by custom_rfid
        $stmt = $db->prepare("SELECT id FROM rfid_cards WHERE custom_uid = ? AND status = 'active'");
        $stmt->execute([$input['customRFID']]);
        $rfidCard = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$rfidCard) {
            throw new Exception('RFID card not found or not active');
        }
        
        // Create or find customer - MODIFIED TO ALWAYS CREATE NEW RECORDS
        $customerId = createCustomerRecord($db, $input);
        
        // Create pet
        $petId = createPet($db, $customerId, $input);
        
        // Create booking
        $bookingId = createBooking($db, $petId, $rfidCard['id'], $input);
        
        // Add services to booking
        if (!empty($input['services'])) {
            addServicesToBooking($db, $bookingId, $input['services']);
        }
        
        // Create initial status update
        createStatusUpdate($db, $bookingId, 'checked-in', 'Initial check-in completed');
        
        // Update booking with welcome email flag
        $stmt = $db->prepare("UPDATE bookings SET welcome_email_sent = 0 WHERE id = ?");
        $stmt->execute([$bookingId]);
        
        // Commit transaction
        $db->commit();
        
          // Try to send emails (after successful booking creation)
        $emailSent = false;
        $trackingEmailSent = false;
        
        try {
            // Send booking confirmation email
            $emailSent = sendBookingConfirmationEmail($bookingId);
            
            // Send tracking link email
            $trackingEmailSent = sendTrackingLinkEmail($bookingId, $input['ownerEmail'], $input['customRFID']);
            
            // Update email sent flags if successful
            if ($emailSent || $trackingEmailSent) {
                $stmt = $db->prepare("UPDATE bookings SET welcome_email_sent = 1 WHERE id = ?");
                $stmt->execute([$bookingId]);
            }
        } catch (Exception $emailError) {
            error_log("Email sending failed: " . $emailError->getMessage());
            // Don't fail the entire booking if email fails
        }
        
        // Remove lock file on success
        if (file_exists($lockFile)) {
            unlink($lockFile);
        }
        
        echo json_encode([
            'success' => true,
            'booking_id' => $bookingId,
            'rfid_tag' => $input['customRFID'],
            'tracking_url' => "guest_dashboard.html?token=" . urlencode($input['customRFID']),
            'message' => 'Check-in completed successfully',
            'email_sent' => $emailSent,
            'tracking_email_sent' => $trackingEmailSent
        ]);
        
    } catch(Exception $e) {
        // Remove lock file on error
        $lockFile = sys_get_temp_dir() . '/booking_lock_' . md5($_SERVER['REMOTE_ADDR'] ?? 'unknown');
        if (file_exists($lockFile)) {
            unlink($lockFile);
        }
        
        if (isset($db) && $db->inTransaction()) {
            $db->rollback();
        }
        
        error_log('Check-in error: ' . $e->getMessage());
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'error' => $e->getMessage()
        ]);
    }
}

// MODIFIED FUNCTION: Always create new customer records for historical purposes
function createCustomerRecord($db, $input) {
    // Always create a new customer record for each booking to maintain history
    // This ensures we have a complete record of each visit/booking
    $stmt = $db->prepare("INSERT INTO customers (name, phone, email) VALUES (?, ?, ?)");
    $stmt->execute([$input['ownerName'], $input['ownerPhone'], $input['ownerEmail']]);
    return $db->lastInsertId();
}

// DEPRECATED: This function was causing the overwrite issue
// Keeping for reference but not using anymore
function findOrCreateCustomer($db, $input) {
    // Check if customer exists by phone
    $stmt = $db->prepare("SELECT id FROM customers WHERE phone = ?");
    $stmt->execute([$input['ownerPhone']]);
    $customer = $stmt->fetch(PDO::FETCH_ASSOC);
    
    if ($customer) {
        // Update customer info - THIS WAS THE PROBLEM
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

function sendTrackingLinkEmail($bookingId, $customerEmail, $customRFID) {
    try {
        $trackingUrl = "http://yourdomain.com/html/guest_dashboard.html?token=" . urlencode($customRFID);
        
        $subject = "Track Your Pet's Grooming Progress - 8Paws Pet Boutique";
        $message = "
        <html>
        <body style='font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;'>
            <div style='background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 20px; text-align: center;'>
                <h1 style='color: white; margin: 0;'>8Paws Pet Boutique</h1>
                <p style='color: white; margin: 5px 0 0 0;'>Pet Grooming & Care Services</p>
            </div>
            <div style='padding: 30px; background: white;'>
                <h2 style='color: #333; margin-bottom: 20px;'>Track Your Pet's Progress</h2>
                <p>Hello! Your pet has been successfully checked in for grooming services.</p>
                <p>You can track your pet's progress in real-time by clicking the link below:</p>
                <div style='text-align: center; margin: 30px 0;'>
                    <a href='{$trackingUrl}' style='background: #667eea; color: white; padding: 15px 30px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block;'>Track My Pet</a>
                </div>
                <p><strong>Booking ID:</strong> #{$bookingId}</p>
                <p><strong>Tracking ID:</strong> {$customRFID}</p>
                <p style='color: #666; font-size: 14px; margin-top: 30px;'>This page will automatically update as your pet moves through our grooming process. You'll receive notifications at each stage!</p>
            </div>
        </body>
        </html>";
        
        $headers = "MIME-Version: 1.0" . "\r\n";
        $headers .= "Content-type:text/html;charset=UTF-8" . "\r\n";
        $headers .= "From: 8Paws Pet Boutique <noreply@8pawspetboutique.com>" . "\r\n";
        
        return mail($customerEmail, $subject, $message, $headers);
        
    } catch(Exception $e) {
        error_log('Tracking email error: ' . $e->getMessage());
        return false;
    }
}
?>