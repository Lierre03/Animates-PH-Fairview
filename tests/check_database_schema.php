<?php
// check_database_schema.php - Check what columns exist in your tables
error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once '../config/database.php';

echo "<h2>Database Schema Check</h2>";

try {
    $db = getDB();
    
    $tables = ['services', 'customers', 'pets', 'bookings', 'booking_services', 'rfid_cards', 'status_updates'];
    
    foreach ($tables as $table) {
        echo "<h3>Table: $table</h3>";
        
        try {
            $stmt = $db->prepare("DESCRIBE $table");
            $stmt->execute();
            $columns = $stmt->fetchAll(PDO::FETCH_ASSOC);
            
            echo "<table border='1' style='border-collapse: collapse; margin-bottom: 20px;'>";
            echo "<tr><th>Field</th><th>Type</th><th>Null</th><th>Key</th><th>Default</th><th>Extra</th></tr>";
            
            foreach ($columns as $column) {
                echo "<tr>";
                echo "<td>" . htmlspecialchars($column['Field']) . "</td>";
                echo "<td>" . htmlspecialchars($column['Type']) . "</td>";
                echo "<td>" . htmlspecialchars($column['Null']) . "</td>";
                echo "<td>" . htmlspecialchars($column['Key']) . "</td>";
                echo "<td>" . htmlspecialchars($column['Default']) . "</td>";
                echo "<td>" . htmlspecialchars($column['Extra']) . "</td>";
                echo "</tr>";
            }
            
            echo "</table>";
        } catch (Exception $e) {
            echo "<p style='color: red;'>Error checking table $table: " . $e->getMessage() . "</p>";
        }
    }
    
} catch (Exception $e) {
    echo "<p style='color: red;'>Database connection error: " . $e->getMessage() . "</p>";
}

echo "<h3>Quick Fix Commands</h3>";
echo "<p>If you need to add the missing duration_minutes column to services table, run this SQL:</p>";
echo "<code style='background: #f5f5f5; padding: 10px; display: block; margin: 10px 0;'>";
echo "ALTER TABLE services ADD COLUMN duration_minutes INT DEFAULT 60 AFTER price;";
echo "</code>";

echo "<p>Or if you prefer to keep the current structure, the fixed PHP code above removes duration_minutes from INSERT statements.</p>";
?>
