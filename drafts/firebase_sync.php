<?php
require_once '../config/database.php';
require_once 'vendor/autoload.php';

use Kreait\Firebase\Factory;

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

class FirebaseSync {
    private $db;
    private $firestore;
    
    public function __construct() {
        $this->db = getDB();
        $this->initFirebase();
    }
    
    private function initFirebase() {
        $factory = (new Factory)
            ->withProjectId('pawsproject-1379a')
            ->withDatabaseUri('https://pawsproject-1379a-default-rtdb.firebaseio.com');
        
        $this->firestore = $factory->createFirestore();
    }
    
    public function checkForNewRFIDData() {
        try {
            // Get the latest Firebase entry
            $collection = $this->firestore->collection('rfid_validations');
            $query = $collection->orderBy('timestamp', 'DESC')->limit(1);
            $documents = $query->documents();
            
            if ($documents->isEmpty()) {
                return ['success' => false, 'message' => 'No RFID data found'];
            }
            
            $latestDoc = null;
            foreach ($documents as $document) {
                $latestDoc = $document;
                break;
            }
            
            $firebaseData = $latestDoc->data();
            
            // Check if this data is already processed
            $lastProcessed = $this->getLastProcessedTimestamp();
            $currentTimestamp = $firebaseData['timestamp']->toDateTime()->format('Y-m-d H:i:s');
            
            if ($lastProcessed >= $currentTimestamp) {
                return ['success' => false, 'message' => 'No new data to process'];
            }
            
            // Process the new data
            $result = $this->processRFIDData($firebaseData);
            
            // Update last processed timestamp
            $this->updateLastProcessedTimestamp($currentTimestamp);
            
            return $result;
            
        } catch(Exception $e) {
            error_log('Firebase sync error: ' . $e->getMessage());
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }
    
    private function processRFIDData($firebaseData) {
        try {
            $this->db->beginTransaction();
            
            // Check if card exists in MySQL
            $stmt = $this->db->prepare("SELECT id, tap_count FROM rfid_cards WHERE card_uid = ?");
            $stmt->execute([$firebaseData['cardUID']]);
            $cardData = $stmt->fetch(PDO::FETCH_ASSOC);
            
            if ($cardData) {
                // Update existing card
                $stmt = $this->db->prepare("UPDATE rfid_cards SET tap_count = ?, max_taps = ?, updated_at = NOW() WHERE id = ?");
                $stmt->execute([$firebaseData['tapCount'], $firebaseData['maxTaps'], $cardData['id']]);
                $cardId = $cardData['id'];
            } else {
                // Insert new card
                $stmt = $this->db->prepare("INSERT INTO rfid_cards (card_uid, custom_uid, tap_count, max_taps) VALUES (?, ?, ?, ?)");
                $stmt->execute([
                    $firebaseData['cardUID'],
                    $firebaseData['customUID'],
                    $firebaseData['tapCount'],
                    $firebaseData['maxTaps']
                ]);
                $cardId = $this->db->lastInsertId();
            }
            
            // Create tap history log
            $stmt = $this->db->prepare("INSERT INTO rfid_tap_history (rfid_card_id, card_uid, custom_uid, tap_number, device_info, wifi_network, signal_strength) VALUES (?, ?, ?, ?, ?, ?, ?)");
            $stmt->execute([
                $cardId,
                $firebaseData['cardUID'],
                $firebaseData['customUID'],
                $firebaseData['tapCount'],
                $firebaseData['deviceInfo'] ?? null,
                $firebaseData['wifiNetwork'] ?? null,
                $firebaseData['signalStrength'] ?? null
            ]);
            
            // If tap count > 1, update pet status
            if ($firebaseData['tapCount'] > 1) {
                $this->updatePetStatus($firebaseData['customUID'], $firebaseData['tapCount']);
            }
            
            $this->db->commit();
            
            return [
                'success' => true,
                'customUID' => $firebaseData['customUID'],
                'tapCount' => $firebaseData['tapCount'],
                'message' => 'RFID data synchronized successfully'
            ];
            
        } catch(Exception $e) {
            $this->db->rollback();
            throw $e;
        }
    }
    
    private function updatePetStatus($customUID, $tapCount) {
        // Find active booking for this RFID
        $stmt = $this->db->prepare("
            SELECT b.id, b.status 
            FROM bookings b 
            WHERE b.custom_rfid = ? 
            AND b.status NOT IN ('completed', 'cancelled')
            ORDER BY b.created_at DESC 
            LIMIT 1
        ");
        $stmt->execute([$customUID]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($booking) {
            $newStatus = $this->getStatusByTapCount($booking['status'], $tapCount);
            if ($newStatus && $newStatus !== $booking['status']) {
                // Update booking status
                $stmt = $this->db->prepare("UPDATE bookings SET status = ?, updated_at = NOW() WHERE id = ?");
                $stmt->execute([$newStatus, $booking['id']]);
                
                // Create status update log
                $stmt = $this->db->prepare("INSERT INTO status_updates (booking_id, status, notes) VALUES (?, ?, ?)");
                $stmt->execute([$booking['id'], $newStatus, "Status updated via RFID tap #{$tapCount}"]);
                
                // Set completion time if status is 'completed'
                if ($newStatus === 'completed') {
                    $stmt = $this->db->prepare("UPDATE bookings SET actual_completion = NOW() WHERE id = ?");
                    $stmt->execute([$booking['id']]);
                }
            }
        }
    }
    
    private function getStatusByTapCount($currentStatus, $tapCount) {
        // Define status progression based on tap count
        $statusMap = [
            2 => 'bathing',
            3 => 'grooming', 
            4 => 'ready'
        ];
        
        return $statusMap[$tapCount] ?? null;
    }
    
    private function getLastProcessedTimestamp() {
        $stmt = $this->db->prepare("SELECT config_value FROM app_config WHERE config_key = 'last_firebase_sync'");
        $stmt->execute();
        $result = $stmt->fetch(PDO::FETCH_ASSOC);
        
        return $result ? $result['config_value'] : '1970-01-01 00:00:00';
    }
    
    private function updateLastProcessedTimestamp($timestamp) {
        $stmt = $this->db->prepare("INSERT INTO app_config (config_key, config_value) VALUES ('last_firebase_sync', ?) ON DUPLICATE KEY UPDATE config_value = ?");
        $stmt->execute([$timestamp, $timestamp]);
    }
}

// Handle requests
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET') {
    $sync = new FirebaseSync();
    $result = $sync->checkForNewRFIDData();
    echo json_encode($result);
} else {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
}
?>