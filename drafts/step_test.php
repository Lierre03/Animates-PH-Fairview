<?php
header('Content-Type: application/json');

$steps = [];
$currentStep = 1;

try {
    // Step 1: Basic PHP
    $steps["step_$currentStep"] = "Basic PHP - OK";
    $currentStep++;
    
    // Step 2: Try to include database file
    if (file_exists('../config/database.php')) {
        $steps["step_$currentStep"] = "database.php file exists - OK";
        $currentStep++;
        
        try {
            require_once '../config/database.php';
            $steps["step_$currentStep"] = "database.php included - OK";
            $currentStep++;
        } catch (Exception $e) {
            throw new Exception("Failed to include database.php: " . $e->getMessage());
        } catch (Error $e) {
            throw new Exception("PHP Error in database.php: " . $e->getMessage());
        }
    } else {
        throw new Exception("database.php file not found at ../config/database.php");
    }
    
    // Step 3: Check if getDB function exists
    if (function_exists('getDB')) {
        $steps["step_$currentStep"] = "getDB() function exists - OK";
        $currentStep++;
    } else {
        throw new Exception("getDB() function not found in database.php");
    }
    
    // Step 4: Try database connection
    try {
        $db = getDB();
        $steps["step_$currentStep"] = "Database connection - OK";
        $currentStep++;
    } catch (Exception $e) {
        throw new Exception("Database connection failed: " . $e->getMessage());
    }
    
    // Step 5: Test simple query
    try {
        $stmt = $db->prepare("SELECT COUNT(*) as count FROM rfid_cards");
        $stmt->execute();
        $result = $stmt->fetch();
        $steps["step_$currentStep"] = "Database query test - OK (found {$result['count']} RFID cards)";
        $currentStep++;
    } catch (Exception $e) {
        throw new Exception("Database query failed: " . $e->getMessage());
    }
    
    // Step 6: Test specific RFID lookup
    try {
        $testRfid = 'CQBPCU8R';
        $stmt = $db->prepare("SELECT id, card_uid, custom_uid, tap_count FROM rfid_cards WHERE card_uid = ? OR custom_uid = ? LIMIT 1");
        $stmt->execute([$testRfid, $testRfid]);
        $result = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if ($result) {
            $steps["step_$currentStep"] = "RFID lookup test - OK (found RFID: $testRfid)";
            $steps["found_data"] = $result;
        } else {
            $steps["step_$currentStep"] = "RFID lookup test - OK (RFID $testRfid not found in database)";
        }
        $currentStep++;
    } catch (Exception $e) {
        throw new Exception("RFID lookup failed: " . $e->getMessage());
    }
    
    // All steps passed
    echo json_encode([
        'success' => true,
        'message' => 'All tests passed! 🎉',
        'steps' => $steps,
        'total_steps' => $currentStep - 1
    ], JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage(),
        'completed_steps' => $steps,
        'failed_at_step' => $currentStep,
        'file' => basename($e->getFile()),
        'line' => $e->getLine()
    ], JSON_PRETTY_PRINT);
} catch (Error $e) {
    echo json_encode([
        'success' => false,
        'message' => 'PHP Fatal Error: ' . $e->getMessage(),
        'completed_steps' => $steps,
        'failed_at_step' => $currentStep,
        'file' => basename($e->getFile()),
        'line' => $e->getLine()
    ], JSON_PRETTY_PRINT);
}
?>