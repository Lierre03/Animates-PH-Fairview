<?php
require_once '../config/database.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

try {
    $db = getDB();
    
    switch($method) {
        case 'GET':
            if ($action === 'get_services') {
                getServicesWithPricing($db);
            } elseif ($action === 'get_pet_sizes') {
                getPetSizes($db);
            } else {
                throw new Exception('Invalid action');
            }
            break;
        default:
            throw new Exception('Method not allowed');
    }
    
} catch(Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}

function getServicesWithPricing($db) {
    try {
        // First check if is_size_based column exists
        $stmt = $db->prepare("SHOW COLUMNS FROM services LIKE 'is_size_based'");
        $stmt->execute();
        $columnExists = $stmt->fetch() !== false;
        
        // Build query based on column existence
        if ($columnExists) {
            $query = "
                SELECT 
                    s.id,
                    s.name,
                    s.description,
                    s.category,
                    s.is_size_based,
                    s.base_price,
                    sp.pet_size,
                    sp.price
                FROM services s
                LEFT JOIN service_pricing sp ON s.id = sp.service_id
                WHERE s.status = 'active'
                ORDER BY 
                    FIELD(s.category, 'basic', 'premium', 'addon'),
                    s.id,
                    FIELD(sp.pet_size, 'small', 'medium', 'large', 'extra_large')
            ";
        } else {
            // Fallback query without is_size_based column
            $query = "
                SELECT 
                    s.id,
                    s.name,
                    s.description,
                    s.category,
                    TRUE as is_size_based,
                    s.base_price,
                    sp.pet_size,
                    sp.price
                FROM services2 s
                LEFT JOIN service_pricing sp ON s.id = sp.service_id
                WHERE s.status = 'active'
                ORDER BY 
                    FIELD(s.category, 'basic', 'premium', 'addon'),
                    s.id,
                    FIELD(sp.pet_size, 'small', 'medium', 'large', 'extra_large')
            ";
        }
        
        $stmt = $db->prepare($query);
        $stmt->execute();
        $results = $stmt->fetchAll(PDO::FETCH_ASSOC);
        
        // Group services and their pricing
        $services = [];
        foreach ($results as $row) {
            $serviceId = $row['id'];
            
            if (!isset($services[$serviceId])) {
                $services[$serviceId] = [
                    'id' => $row['id'],
                    'name' => $row['name'],
                    'description' => $row['description'],
                    'category' => $row['category'],
                    'is_size_based' => (bool)$row['is_size_based'],
                    'base_price' => isset($row['base_price']) ? floatval($row['base_price']) : 0,
                    'pricing' => []
                ];
            }
            
            if ($row['pet_size'] && $row['price']) {
                $services[$serviceId]['pricing'][$row['pet_size']] = floatval($row['price']);
            }
        }
        
        // Convert to indexed array grouped by category
        $groupedServices = [
            'basic' => [],
            'premium' => [],
            'addon' => []
        ];
        
        foreach ($services as $service) {
            $groupedServices[$service['category']][] = $service;
        }
        
        echo json_encode([
            'success' => true,
            'services' => $groupedServices
        ]);
        
    } catch(Exception $e) {
        throw new Exception('Failed to fetch services: ' . $e->getMessage());
    }
}
?>