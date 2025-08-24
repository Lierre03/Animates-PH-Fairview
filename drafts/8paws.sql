-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: localhost
-- Generation Time: Aug 20, 2025 at 02:08 AM
-- Server version: 10.4.28-MariaDB
-- PHP Version: 8.2.4

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `8paws`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `LinkCustomerToUser` (IN `p_user_id` INT, IN `p_phone` VARCHAR(20))   BEGIN
    DECLARE customer_exists INT DEFAULT 0;
    
    -- Check if customer exists with this phone
    SELECT COUNT(*) INTO customer_exists 
    FROM customers 
    WHERE phone = p_phone AND user_id IS NULL;
    
    IF customer_exists > 0 THEN
        -- Update customer record to link with user
        UPDATE customers 
        SET user_id = p_user_id, 
            created_via = 'online',
            updated_at = NOW()
        WHERE phone = p_phone AND user_id IS NULL;
        
        -- Link all pets of this customer to the user
        INSERT INTO user_pets (user_id, pet_id, is_primary_owner)
        SELECT p_user_id, p.id, TRUE
        FROM pets p
        JOIN customers c ON p.customer_id = c.id
        WHERE c.phone = p_phone AND c.user_id = p_user_id;
        
        -- Link all bookings to the user
        UPDATE bookings b
        JOIN pets p ON b.pet_id = p.id
        JOIN customers c ON p.customer_id = c.id
        SET b.user_id = p_user_id, 
            b.booking_type = 'online',
            b.updated_at = NOW()
        WHERE c.user_id = p_user_id AND b.user_id IS NULL;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `UpdatePetStatusByRFID` (IN `p_custom_uid` VARCHAR(8), IN `p_tap_count` INT)   BEGIN
    DECLARE v_booking_id INT;
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_new_status VARCHAR(20);
    
    
    SELECT id, status INTO v_booking_id, v_current_status
    FROM bookings 
    WHERE custom_rfid = p_custom_uid 
    AND status NOT IN ('completed', 'cancelled')
    ORDER BY created_at DESC 
    LIMIT 1;
    
    IF v_booking_id IS NOT NULL THEN
        
        SET v_new_status = CASE p_tap_count
            WHEN 2 THEN 'bathing'
            WHEN 3 THEN 'grooming'
            WHEN 4 THEN 'ready'
            ELSE v_current_status
        END;
        
        
        IF v_new_status != v_current_status THEN
            UPDATE bookings 
            SET status = v_new_status,
                actual_completion = CASE WHEN v_new_status = 'completed' THEN NOW() ELSE actual_completion END,
                updated_at = NOW()
            WHERE id = v_booking_id;
            
            
            INSERT INTO status_updates (booking_id, status, notes)
            VALUES (v_booking_id, v_new_status, CONCAT('Status updated via RFID tap #', p_tap_count));
        END IF;
    END IF;
END$$

--
-- Functions
--
CREATE DEFINER=`root`@`localhost` FUNCTION `GetUserActiveBookingsCount` (`p_user_id` INT) RETURNS INT(11) DETERMINISTIC READS SQL DATA BEGIN
    DECLARE booking_count INT DEFAULT 0;
    
    SELECT COUNT(*) INTO booking_count
    FROM bookings b
    WHERE b.user_id = p_user_id 
    AND b.status NOT IN ('completed', 'cancelled');
    
    RETURN booking_count;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `appointments`
--

CREATE TABLE `appointments` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `pet_id` int(11) NOT NULL,
  `appointment_date` date NOT NULL,
  `appointment_time` time NOT NULL,
  `estimated_duration` int(11) DEFAULT 120,
  `status` enum('scheduled','confirmed','in_progress','completed','cancelled','no_show') DEFAULT 'scheduled',
  `total_amount` decimal(10,2) DEFAULT 0.00,
  `special_instructions` text DEFAULT NULL,
  `staff_notes` text DEFAULT NULL,
  `reminder_sent` tinyint(1) DEFAULT 0,
  `confirmation_sent` tinyint(1) DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `appointment_services`
--

CREATE TABLE `appointment_services` (
  `id` int(11) NOT NULL,
  `appointment_id` int(11) NOT NULL,
  `service_id` int(11) NOT NULL,
  `price` decimal(8,2) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `app_config`
--

CREATE TABLE `app_config` (
  `id` int(11) NOT NULL,
  `config_key` varchar(100) NOT NULL,
  `config_value` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `app_config`
--

INSERT INTO `app_config` (`id`, `config_key`, `config_value`, `created_at`, `updated_at`) VALUES
(1, 'last_firebase_sync', '1970-01-01 00:00:00', '2025-08-16 18:41:01', '2025-08-16 18:41:01');

-- --------------------------------------------------------

--
-- Table structure for table `bookings`
--

CREATE TABLE `bookings` (
  `id` int(11) NOT NULL,
  `pet_id` int(11) NOT NULL,
  `rfid_card_id` int(11) DEFAULT NULL,
  `rfid_tag_id` int(11) DEFAULT NULL,
  `custom_rfid` varchar(8) DEFAULT NULL,
  `total_amount` decimal(10,2) NOT NULL,
  `status` enum('checked-in','bathing','grooming','ready','completed','cancelled') DEFAULT 'checked-in',
  `check_in_time` timestamp NOT NULL DEFAULT current_timestamp(),
  `estimated_completion` timestamp NULL DEFAULT NULL,
  `actual_completion` timestamp NULL DEFAULT NULL,
  `pickup_time` timestamp NULL DEFAULT NULL,
  `staff_notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `user_id` int(11) DEFAULT NULL,
  `booking_type` enum('walk_in','online') DEFAULT 'walk_in',
  `welcome_email_sent` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `bookings`
--

INSERT INTO `bookings` (`id`, `pet_id`, `rfid_card_id`, `rfid_tag_id`, `custom_rfid`, `total_amount`, `status`, `check_in_time`, `estimated_completion`, `actual_completion`, `pickup_time`, `staff_notes`, `created_at`, `updated_at`, `user_id`, `booking_type`, `welcome_email_sent`) VALUES
(34, 56, NULL, NULL, '5TKVETUH', 600.00, 'completed', '2025-08-17 17:05:12', '2025-08-17 19:05:12', NULL, NULL, NULL, '2025-08-17 17:05:12', '2025-08-17 17:07:14', NULL, 'walk_in', 0),
(35, 57, NULL, NULL, '5TKVETUH', 400.00, 'completed', '2025-08-17 17:06:21', '2025-08-17 19:06:21', NULL, NULL, NULL, '2025-08-17 17:06:21', '2025-08-17 17:07:06', NULL, 'walk_in', 0),
(36, 58, 27, NULL, 'VQB5J7E7', 350.00, 'completed', '2025-08-17 17:30:25', '2025-08-17 19:30:25', NULL, NULL, NULL, '2025-08-17 17:30:25', '2025-08-17 17:34:10', NULL, 'walk_in', 0),
(37, 59, 28, NULL, 'U6DKP4UZ', 600.00, 'completed', '2025-08-17 17:32:33', '2025-08-17 19:32:33', NULL, NULL, NULL, '2025-08-17 17:32:33', '2025-08-17 19:05:18', NULL, 'walk_in', 0),
(38, 60, 29, NULL, '1HQCNMXF', 650.00, 'completed', '2025-08-17 17:34:30', '2025-08-17 19:34:30', NULL, NULL, NULL, '2025-08-17 17:34:30', '2025-08-17 18:03:27', NULL, 'walk_in', 0),
(39, 61, 29, NULL, '5QMJDTLZ', 700.00, 'completed', '2025-08-17 18:03:57', '2025-08-17 20:03:57', NULL, NULL, NULL, '2025-08-17 18:03:57', '2025-08-17 18:40:54', NULL, 'walk_in', 0),
(40, 62, 30, NULL, 'MLG7ZS6K', 1050.00, 'completed', '2025-08-17 18:12:26', '2025-08-17 20:12:26', NULL, NULL, NULL, '2025-08-17 18:12:26', '2025-08-17 18:26:05', NULL, 'walk_in', 0),
(41, 63, 26, NULL, 'NPMCNGE5', 750.00, 'completed', '2025-08-17 18:29:41', '2025-08-17 20:29:41', NULL, NULL, NULL, '2025-08-17 18:29:41', '2025-08-17 18:57:27', NULL, 'walk_in', 0),
(42, 64, 30, NULL, '6KVLB5U4', 750.00, 'completed', '2025-08-17 18:42:54', '2025-08-17 20:42:54', NULL, NULL, NULL, '2025-08-17 18:42:54', '2025-08-17 19:01:28', NULL, 'walk_in', 0),
(43, 65, 26, NULL, 'FKRE30QH', 1050.00, 'completed', '2025-08-17 18:57:59', '2025-08-17 20:57:59', NULL, NULL, NULL, '2025-08-17 18:57:59', '2025-08-18 03:45:40', NULL, 'walk_in', 0),
(44, 66, 30, NULL, 'EGM9UCJG', 1000.00, 'completed', '2025-08-17 19:01:56', '2025-08-17 21:01:56', NULL, NULL, NULL, '2025-08-17 19:01:56', '2025-08-18 05:25:59', NULL, 'walk_in', 0),
(45, 67, 28, NULL, 'BK02IOXP', 1300.00, 'completed', '2025-08-17 19:05:49', '2025-08-17 21:05:49', NULL, NULL, NULL, '2025-08-17 19:05:49', '2025-08-18 05:37:50', NULL, 'walk_in', 0),
(46, 68, 29, NULL, 'CWGLF50P', 850.00, 'completed', '2025-08-17 19:10:20', '2025-08-17 21:10:20', NULL, NULL, NULL, '2025-08-17 19:10:20', '2025-08-18 04:43:05', NULL, 'walk_in', 0),
(47, 69, 31, NULL, 'TBAXNIWH', 1800.00, 'completed', '2025-08-18 03:37:05', '2025-08-18 05:37:05', NULL, NULL, NULL, '2025-08-18 03:37:05', '2025-08-18 05:18:55', NULL, 'walk_in', 0),
(48, 70, 32, NULL, 'KLHNUIT1', 2150.00, 'completed', '2025-08-18 03:41:36', '2025-08-18 05:41:36', NULL, NULL, NULL, '2025-08-18 03:41:36', '2025-08-18 10:23:09', NULL, 'walk_in', 0),
(49, 71, 26, NULL, '3ZWM7N2Z', 2150.00, 'completed', '2025-08-18 03:46:08', '2025-08-18 05:46:08', NULL, NULL, NULL, '2025-08-18 03:46:08', '2025-08-18 04:36:56', NULL, 'walk_in', 0),
(50, 72, 26, NULL, 'BKEP0GSH', 850.00, 'completed', '2025-08-18 04:37:22', '2025-08-18 06:37:22', NULL, NULL, NULL, '2025-08-18 04:37:22', '2025-08-18 06:00:50', NULL, 'walk_in', 0),
(51, 73, 29, NULL, '3XI4R1M2', 2150.00, 'completed', '2025-08-18 04:43:34', '2025-08-18 06:43:34', NULL, NULL, NULL, '2025-08-18 04:43:34', '2025-08-18 06:05:17', NULL, 'walk_in', 0),
(52, 74, 31, NULL, 'W7WV38JR', 1400.00, 'completed', '2025-08-18 05:19:55', '2025-08-18 07:19:55', NULL, NULL, NULL, '2025-08-18 05:19:55', '2025-08-18 12:19:55', NULL, 'walk_in', 0),
(53, 75, 27, NULL, 'QWOU8RIT', 2150.00, 'completed', '2025-08-18 05:24:16', '2025-08-18 07:24:16', NULL, NULL, NULL, '2025-08-18 05:24:16', '2025-08-18 10:26:08', NULL, 'walk_in', 0),
(54, 76, 30, NULL, 'PHOX6NAW', 2150.00, 'completed', '2025-08-18 05:26:26', '2025-08-18 07:26:26', NULL, NULL, NULL, '2025-08-18 05:26:26', '2025-08-18 05:47:48', NULL, 'walk_in', 0),
(55, 77, 28, NULL, 'NTY2EYHS', 1200.00, 'completed', '2025-08-18 05:38:15', '2025-08-18 07:38:15', NULL, NULL, NULL, '2025-08-18 05:38:15', '2025-08-18 05:41:53', NULL, 'walk_in', 0),
(56, 78, 28, NULL, 'DPHJS82Z', 850.00, 'completed', '2025-08-18 05:42:19', '2025-08-18 07:42:19', NULL, NULL, NULL, '2025-08-18 05:42:19', '2025-08-18 10:28:54', NULL, 'walk_in', 0),
(57, 79, 30, NULL, 'XP29VP42', 1400.00, 'completed', '2025-08-18 05:48:36', '2025-08-18 07:48:36', NULL, NULL, NULL, '2025-08-18 05:48:36', '2025-08-18 17:20:19', NULL, 'walk_in', 0),
(58, 80, 26, NULL, '313IW8SK', 1500.00, 'completed', '2025-08-18 06:04:31', '2025-08-18 08:04:31', NULL, NULL, NULL, '2025-08-18 06:04:31', '2025-08-18 09:22:51', NULL, 'walk_in', 0),
(59, 81, 29, NULL, 'SU47TXJ9', 2150.00, 'completed', '2025-08-18 06:05:43', '2025-08-18 08:05:43', NULL, NULL, NULL, '2025-08-18 06:05:43', '2025-08-18 09:33:02', NULL, 'walk_in', 0),
(60, 82, NULL, NULL, '3A7YRMAL', 1300.00, 'ready', '2025-08-18 09:23:18', '2025-08-18 11:23:18', NULL, NULL, NULL, '2025-08-18 09:23:18', '2025-08-18 10:36:49', NULL, 'walk_in', 0),
(61, 83, NULL, NULL, '3A7YRMAL', 1300.00, 'completed', '2025-08-18 09:23:21', '2025-08-18 11:23:21', NULL, NULL, NULL, '2025-08-18 09:23:21', '2025-08-18 10:36:43', NULL, 'walk_in', 0),
(62, 84, NULL, NULL, '3A7YRMAL', 1300.00, 'completed', '2025-08-18 09:23:28', '2025-08-18 11:23:28', NULL, NULL, NULL, '2025-08-18 09:23:28', '2025-08-18 10:36:27', NULL, 'walk_in', 0),
(63, 85, NULL, NULL, '3A7YRMAL', 1300.00, 'completed', '2025-08-18 09:23:28', '2025-08-18 11:23:28', NULL, NULL, NULL, '2025-08-18 09:23:28', '2025-08-18 10:36:35', NULL, 'walk_in', 0),
(64, 86, 29, NULL, 'A18WIJFW', 1050.00, 'completed', '2025-08-18 09:42:25', '2025-08-18 11:42:25', NULL, NULL, NULL, '2025-08-18 09:42:25', '2025-08-19 04:11:41', NULL, 'walk_in', 1),
(65, 87, 32, NULL, 'UUVNMQRS', 500.00, 'completed', '2025-08-18 10:23:37', '2025-08-18 12:23:37', NULL, NULL, NULL, '2025-08-18 10:23:37', '2025-08-18 17:56:47', NULL, 'walk_in', 1),
(66, 88, 27, NULL, 'MLG7ZS6K', 1350.00, 'completed', '2025-08-18 10:26:35', '2025-08-18 12:26:35', NULL, NULL, NULL, '2025-08-18 10:26:35', '2025-08-19 04:15:10', NULL, 'walk_in', 1),
(67, 89, 28, NULL, '46NWEJPB', 850.00, 'completed', '2025-08-18 10:29:20', '2025-08-18 12:29:20', NULL, NULL, NULL, '2025-08-18 10:29:20', '2025-08-19 03:33:27', NULL, 'walk_in', 1),
(68, 90, 26, NULL, 'A3ESN3KH', 1550.00, 'completed', '2025-08-18 10:36:54', '2025-08-18 12:36:54', NULL, NULL, NULL, '2025-08-18 10:36:54', '2025-08-18 10:50:25', NULL, 'walk_in', 1),
(69, 91, 26, NULL, 'CUPYNJS1', 900.00, 'completed', '2025-08-18 10:50:40', '2025-08-18 12:50:40', NULL, NULL, NULL, '2025-08-18 10:50:40', '2025-08-18 12:50:09', NULL, 'walk_in', 1),
(70, 92, 31, NULL, '3ZJZPV7R', 800.00, 'checked-in', '2025-08-18 12:20:24', '2025-08-18 14:20:24', NULL, NULL, NULL, '2025-08-18 12:20:24', '2025-08-18 12:20:34', NULL, 'walk_in', 1),
(71, 93, 26, NULL, 'MHB2Q4YI', 450.00, 'completed', '2025-08-18 12:50:37', '2025-08-18 14:50:37', NULL, NULL, NULL, '2025-08-18 12:50:37', '2025-08-18 13:07:37', NULL, 'walk_in', 1),
(72, 94, 26, NULL, '7L1YIT8M', 1150.00, 'checked-in', '2025-08-18 13:08:06', '2025-08-18 15:08:06', NULL, NULL, NULL, '2025-08-18 13:08:06', '2025-08-18 13:08:12', NULL, 'walk_in', 1),
(73, 95, 30, NULL, 'I0YCJQDQ', 1050.00, 'completed', '2025-08-18 17:20:47', '2025-08-18 19:20:47', '2025-08-18 17:21:50', NULL, NULL, '2025-08-18 17:20:47', '2025-08-18 17:50:47', NULL, 'walk_in', 1),
(74, 96, 30, NULL, '1Q1P2B44', 550.00, 'ready', '2025-08-18 17:50:54', '2025-08-18 19:50:54', '2025-08-18 17:52:27', NULL, NULL, '2025-08-18 17:50:54', '2025-08-18 17:52:27', NULL, 'walk_in', 1),
(75, 97, 32, NULL, 'X0DL0PCN', 200.00, 'ready', '2025-08-18 17:57:47', '2025-08-18 19:57:47', '2025-08-18 17:58:46', NULL, NULL, '2025-08-18 17:57:47', '2025-08-18 17:58:46', NULL, 'walk_in', 1),
(76, 98, 28, NULL, '5OCP6XFN', 1200.00, 'completed', '2025-08-19 03:34:12', '2025-08-19 05:34:12', '2025-08-19 03:36:07', NULL, NULL, '2025-08-19 03:34:12', '2025-08-19 03:36:07', NULL, 'walk_in', 1),
(77, 99, 28, NULL, 'I4OPS0V5', 1400.00, 'completed', '2025-08-19 03:43:28', '2025-08-19 05:43:28', '2025-08-19 03:44:45', NULL, NULL, '2025-08-19 03:43:28', '2025-08-19 03:44:45', NULL, 'walk_in', 1),
(78, 100, 28, NULL, 'V06LWCWV', 700.00, 'completed', '2025-08-19 03:55:36', '2025-08-19 05:55:36', '2025-08-19 03:57:08', NULL, NULL, '2025-08-19 03:55:36', '2025-08-19 03:57:08', NULL, 'walk_in', 1),
(79, 101, 29, NULL, 'LJVLYGJB', 1050.00, 'completed', '2025-08-19 04:12:24', '2025-08-19 06:12:24', '2025-08-19 04:18:33', NULL, NULL, '2025-08-19 04:12:24', '2025-08-19 04:18:33', NULL, 'walk_in', 1),
(80, 102, 27, NULL, 'TU8A4I60', 850.00, 'completed', '2025-08-19 04:15:56', '2025-08-19 06:15:56', '2025-08-19 04:17:56', NULL, NULL, '2025-08-19 04:15:56', '2025-08-19 04:17:56', NULL, 'walk_in', 1),
(81, 103, 28, NULL, 'PUW7G5B6', 450.00, 'completed', '2025-08-19 04:30:39', '2025-08-19 06:30:39', '2025-08-19 04:31:48', NULL, NULL, '2025-08-19 04:30:39', '2025-08-19 04:31:48', NULL, 'walk_in', 1),
(82, 104, 28, NULL, 'ORR6PDB7', 750.00, 'completed', '2025-08-19 05:41:47', '2025-08-19 07:41:47', '2025-08-19 05:51:43', NULL, NULL, '2025-08-19 05:41:47', '2025-08-19 05:51:43', NULL, 'walk_in', 1),
(83, 105, 28, NULL, 'DQOVZW0I', 950.00, 'completed', '2025-08-19 05:53:04', '2025-08-19 07:53:04', '2025-08-19 05:58:05', NULL, NULL, '2025-08-19 05:53:04', '2025-08-19 05:58:05', NULL, 'walk_in', 1);

-- --------------------------------------------------------

--
-- Stand-in structure for view `booking_rfid_view`
-- (See below for the actual view)
--
CREATE TABLE `booking_rfid_view` (
`booking_id` int(11)
,`custom_rfid` varchar(8)
,`status` enum('checked-in','bathing','grooming','ready','completed','cancelled')
,`total_amount` decimal(10,2)
,`check_in_time` timestamp
,`estimated_completion` timestamp
,`actual_completion` timestamp
,`pet_name` varchar(255)
,`pet_type` varchar(50)
,`pet_breed` varchar(255)
,`owner_name` varchar(255)
,`owner_phone` varchar(20)
,`owner_email` varchar(255)
,`tap_count` int(11)
,`max_taps` int(11)
,`card_uid` varchar(50)
,`status_description` varchar(25)
);

-- --------------------------------------------------------

--
-- Table structure for table `booking_services`
--

CREATE TABLE `booking_services` (
  `id` int(11) NOT NULL,
  `booking_id` int(11) NOT NULL,
  `service_id` int(11) NOT NULL,
  `price` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `booking_services`
--

INSERT INTO `booking_services` (`id`, `booking_id`, `service_id`, `price`) VALUES
(51, 34, 3, 200.00),
(52, 34, 5, 250.00),
(53, 34, 8, 150.00),
(54, 35, 6, 400.00),
(55, 36, 2, 150.00),
(56, 36, 3, 200.00),
(57, 37, 4, 600.00),
(58, 38, 5, 250.00),
(59, 38, 6, 400.00),
(60, 39, 4, 600.00),
(61, 39, 7, 100.00),
(62, 40, 1, 300.00),
(63, 40, 4, 600.00),
(64, 40, 8, 150.00),
(65, 41, 3, 200.00),
(66, 41, 6, 400.00),
(67, 41, 8, 150.00),
(68, 42, 3, 200.00),
(69, 42, 6, 400.00),
(70, 42, 8, 150.00),
(71, 43, 1, 300.00),
(72, 43, 4, 600.00),
(73, 43, 8, 150.00),
(74, 44, 1, 300.00),
(75, 44, 4, 600.00),
(76, 44, 7, 100.00),
(77, 45, 3, 200.00),
(78, 45, 4, 600.00),
(79, 45, 6, 400.00),
(80, 45, 7, 100.00),
(81, 46, 2, 150.00),
(82, 46, 4, 600.00),
(83, 46, 7, 100.00),
(84, 47, 1, 300.00),
(85, 47, 2, 150.00),
(86, 47, 4, 600.00),
(87, 47, 5, 250.00),
(88, 47, 6, 400.00),
(89, 47, 7, 100.00),
(90, 48, 1, 300.00),
(91, 48, 2, 150.00),
(92, 48, 3, 200.00),
(93, 48, 4, 600.00),
(94, 48, 5, 250.00),
(95, 48, 6, 400.00),
(96, 48, 7, 100.00),
(97, 48, 8, 150.00),
(98, 49, 1, 300.00),
(99, 49, 2, 150.00),
(100, 49, 3, 200.00),
(101, 49, 4, 600.00),
(102, 49, 5, 250.00),
(103, 49, 6, 400.00),
(104, 49, 7, 100.00),
(105, 49, 8, 150.00),
(106, 50, 2, 150.00),
(107, 50, 4, 600.00),
(108, 50, 7, 100.00),
(109, 51, 1, 300.00),
(110, 51, 2, 150.00),
(111, 51, 3, 200.00),
(112, 51, 4, 600.00),
(113, 51, 5, 250.00),
(114, 51, 6, 400.00),
(115, 51, 7, 100.00),
(116, 51, 8, 150.00),
(117, 52, 1, 300.00),
(118, 52, 2, 150.00),
(119, 52, 4, 600.00),
(120, 52, 5, 250.00),
(121, 52, 7, 100.00),
(122, 53, 1, 300.00),
(123, 53, 2, 150.00),
(124, 53, 3, 200.00),
(125, 53, 4, 600.00),
(126, 53, 5, 250.00),
(127, 53, 6, 400.00),
(128, 53, 7, 100.00),
(129, 53, 8, 150.00),
(130, 54, 1, 300.00),
(131, 54, 2, 150.00),
(132, 54, 3, 200.00),
(133, 54, 4, 600.00),
(134, 54, 5, 250.00),
(135, 54, 6, 400.00),
(136, 54, 7, 100.00),
(137, 54, 8, 150.00),
(138, 55, 1, 300.00),
(139, 55, 2, 150.00),
(140, 55, 4, 600.00),
(141, 55, 8, 150.00),
(142, 56, 2, 150.00),
(143, 56, 4, 600.00),
(144, 56, 7, 100.00),
(145, 57, 1, 300.00),
(146, 57, 2, 150.00),
(147, 57, 3, 200.00),
(148, 57, 5, 250.00),
(149, 57, 6, 400.00),
(150, 57, 7, 100.00),
(151, 58, 4, 600.00),
(152, 58, 5, 250.00),
(153, 58, 6, 400.00),
(154, 58, 7, 100.00),
(155, 58, 8, 150.00),
(156, 59, 1, 300.00),
(157, 59, 2, 150.00),
(158, 59, 3, 200.00),
(159, 59, 4, 600.00),
(160, 59, 5, 250.00),
(161, 59, 6, 400.00),
(162, 59, 7, 100.00),
(163, 59, 8, 150.00),
(164, 60, 2, 150.00),
(165, 60, 4, 600.00),
(166, 60, 6, 400.00),
(167, 60, 8, 150.00),
(168, 61, 2, 150.00),
(169, 61, 4, 600.00),
(170, 61, 6, 400.00),
(171, 61, 8, 150.00),
(172, 62, 2, 150.00),
(173, 62, 4, 600.00),
(174, 62, 6, 400.00),
(175, 62, 8, 150.00),
(176, 63, 2, 150.00),
(177, 63, 4, 600.00),
(178, 63, 6, 400.00),
(179, 63, 8, 150.00),
(180, 64, 3, 200.00),
(181, 64, 4, 600.00),
(182, 64, 7, 100.00),
(183, 64, 8, 150.00),
(184, 65, 2, 150.00),
(185, 65, 5, 250.00),
(186, 65, 7, 100.00),
(187, 66, 1, 300.00),
(188, 66, 2, 150.00),
(189, 66, 3, 200.00),
(190, 66, 4, 600.00),
(191, 66, 7, 100.00),
(192, 67, 2, 150.00),
(193, 67, 3, 200.00),
(194, 67, 6, 400.00),
(195, 67, 7, 100.00),
(196, 68, 1, 300.00),
(197, 68, 2, 150.00),
(198, 68, 4, 600.00),
(199, 68, 6, 400.00),
(200, 68, 7, 100.00),
(201, 69, 2, 150.00),
(202, 69, 4, 600.00),
(203, 69, 8, 150.00),
(204, 70, 1, 300.00),
(205, 70, 2, 150.00),
(206, 70, 5, 250.00),
(207, 70, 7, 100.00),
(208, 71, 3, 200.00),
(209, 71, 5, 250.00),
(210, 72, 3, 200.00),
(211, 72, 4, 600.00),
(212, 72, 5, 250.00),
(213, 72, 7, 100.00),
(214, 73, 1, 300.00),
(215, 73, 2, 150.00),
(216, 73, 3, 200.00),
(217, 73, 5, 250.00),
(218, 73, 8, 150.00),
(219, 74, 3, 200.00),
(220, 74, 5, 250.00),
(221, 74, 7, 100.00),
(222, 75, 3, 200.00),
(223, 76, 1, 300.00),
(224, 76, 2, 150.00),
(225, 76, 4, 600.00),
(226, 76, 8, 150.00),
(227, 77, 1, 300.00),
(228, 77, 2, 150.00),
(229, 77, 3, 200.00),
(230, 77, 5, 250.00),
(231, 77, 6, 400.00),
(232, 77, 7, 100.00),
(233, 78, 1, 300.00),
(234, 78, 5, 250.00),
(235, 78, 8, 150.00),
(236, 79, 1, 300.00),
(237, 79, 2, 150.00),
(238, 79, 3, 200.00),
(239, 79, 5, 250.00),
(240, 79, 8, 150.00),
(241, 80, 4, 600.00),
(242, 80, 5, 250.00),
(243, 81, 3, 200.00),
(244, 81, 5, 250.00),
(245, 82, 4, 600.00),
(246, 82, 8, 150.00),
(247, 83, 3, 200.00),
(248, 83, 4, 600.00),
(249, 83, 8, 150.00);

-- --------------------------------------------------------

--
-- Table structure for table `customers`
--

CREATE TABLE `customers` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `phone` varchar(20) NOT NULL,
  `email` varchar(255) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `emergency_contact` varchar(20) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `user_id` int(11) DEFAULT NULL,
  `created_via` enum('walk_in','online') DEFAULT 'walk_in'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `customers`
--

INSERT INTO `customers` (`id`, `name`, `phone`, `email`, `address`, `emergency_contact`, `created_at`, `updated_at`, `user_id`, `created_via`) VALUES
(17, 'Bryant Iverson C. Melliza', '0943-135-9316', 'athegreat124@gmail.com', NULL, NULL, '2025-08-17 17:05:12', '2025-08-19 04:15:56', NULL, 'walk_in'),
(18, 'Bryant Iverson C. Melliza', '0939-817-0375', 'bryantiversonmelliza03@gmail.com', NULL, NULL, '2025-08-18 04:43:34', '2025-08-19 03:34:12', NULL, 'walk_in'),
(19, 'Ivy Rivera', '0943-131-2312', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-19 03:43:28', '2025-08-19 03:43:28', NULL, 'walk_in'),
(20, 'Bryant Iverson C. Melliza', '0931-425-6346', 'bryantiversonmelliza03@gmail.com', NULL, NULL, '2025-08-19 03:55:36', '2025-08-19 04:12:24', NULL, 'walk_in'),
(21, 'Iverson melliza', '0939-817-0375', 'bryantiversonmelliza@gmail.com', NULL, NULL, '2025-08-19 04:30:39', '2025-08-19 04:30:39', NULL, 'walk_in'),
(22, 'Bryant Iverson C. Melliza', '0939-817-0375', 'bryantiversonmelliza03@gmail.com', NULL, NULL, '2025-08-19 05:41:47', '2025-08-19 05:41:47', NULL, 'walk_in'),
(23, 'Bryant Iverson C. Melliza', '0943-135-9316', 'bryantiversonmelliza03@gmail.com', NULL, NULL, '2025-08-19 05:53:04', '2025-08-19 05:53:04', NULL, 'walk_in');

-- --------------------------------------------------------

--
-- Table structure for table `pets`
--

CREATE TABLE `pets` (
  `id` int(11) NOT NULL,
  `customer_id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `type` varchar(50) NOT NULL,
  `pet_type` varchar(50) DEFAULT NULL,
  `breed` varchar(255) NOT NULL,
  `age_range` enum('puppy','young','adult','senior') DEFAULT NULL,
  `size` enum('small','medium','large','xlarge') DEFAULT NULL,
  `special_notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `pets`
--

INSERT INTO `pets` (`id`, `customer_id`, `name`, `type`, `pet_type`, `breed`, `age_range`, `size`, `special_notes`, `created_at`, `updated_at`) VALUES
(56, 17, 'owley', 'cat', 'cat', 'American Curl', 'young', 'large', '', '2025-08-17 17:05:12', '2025-08-17 17:05:12'),
(57, 17, 'bianca', 'dog', 'dog', 'african', 'young', 'medium', '', '2025-08-17 17:06:21', '2025-08-17 17:06:21'),
(58, 17, 'owley', 'cat', 'cat', 'American Bobtail', 'young', 'medium', '', '2025-08-17 17:30:25', '2025-08-17 17:30:25'),
(59, 17, 'tanggol', 'dog', 'dog', 'beagle', 'young', 'small', '', '2025-08-17 17:32:33', '2025-08-17 17:32:33'),
(60, 17, 'bianca', 'cat', 'cat', 'Aegean', 'young', 'medium', '', '2025-08-17 17:34:30', '2025-08-17 17:34:30'),
(61, 17, 'owley', 'cat', 'cat', 'Bambino', 'young', 'medium', '', '2025-08-17 18:03:57', '2025-08-17 18:03:57'),
(62, 17, 'ollie', 'Lobster', 'Lobster', 'Buttered Lobster', 'young', 'medium', '', '2025-08-17 18:12:26', '2025-08-17 18:12:26'),
(63, 17, 'owley', 'Lobster', 'Lobster', 'Buttered Lobster', 'young', 'small', '', '2025-08-17 18:29:41', '2025-08-17 18:29:41'),
(64, 17, 'catcatt', 'cat', 'cat', 'American Bobtail', 'young', 'medium', '', '2025-08-17 18:42:54', '2025-08-17 18:42:54'),
(65, 17, 'bianca', 'dog', 'dog', 'african', 'adult', 'medium', '', '2025-08-17 18:57:59', '2025-08-17 18:57:59'),
(66, 17, 'owley', 'dog', 'dog', 'african', 'young', 'small', '', '2025-08-17 19:01:56', '2025-08-17 19:01:56'),
(67, 17, 'tuklaw', 'cat', 'cat', 'Somali', 'young', 'small', '', '2025-08-17 19:05:49', '2025-08-17 19:05:49'),
(68, 17, 'owley', 'cat', 'cat', 'American Bobtail', 'young', 'small', '', '2025-08-17 19:10:20', '2025-08-17 19:10:20'),
(69, 17, 'tanggol', 'dog', 'dog', 'african', 'young', 'small', '', '2025-08-18 03:37:05', '2025-08-18 03:37:05'),
(70, 17, 'owley', 'cat', 'cat', 'Abyssinian', 'young', 'small', '', '2025-08-18 03:41:36', '2025-08-18 03:41:36'),
(71, 17, 'owley', 'cat', 'cat', 'Maine Coon', 'young', 'medium', '', '2025-08-18 03:46:08', '2025-08-18 03:46:08'),
(72, 17, 'owley', 'cat', 'cat', 'Arabian Mau', 'young', 'small', 'sharp claws and aggressive towards stranger', '2025-08-18 04:37:22', '2025-08-18 04:37:22'),
(73, 18, 'tanggol', 'dog', 'dog', 'akita', 'young', 'small', 'Cute lang ganon', '2025-08-18 04:43:34', '2025-08-18 04:43:34'),
(74, 18, 'tanggol', 'dog', 'dog', 'african', 'young', 'medium', '', '2025-08-18 05:19:55', '2025-08-18 05:19:55'),
(75, 17, 'owley', 'dog', 'dog', 'african', 'adult', 'medium', 'hehehe', '2025-08-18 05:24:16', '2025-08-18 05:24:16'),
(76, 17, 'tanggol', 'dog', 'dog', 'buhund', 'young', 'large', '', '2025-08-18 05:26:26', '2025-08-18 05:26:26'),
(77, 17, 'owley', 'dog', 'dog', 'airedale', 'adult', 'large', '', '2025-08-18 05:38:15', '2025-08-18 05:38:15'),
(78, 17, 'owley', 'cat', 'cat', 'Aegean', 'young', 'medium', '', '2025-08-18 05:42:19', '2025-08-18 05:42:19'),
(79, 17, 'tanggol', 'dog', 'dog', 'basenji', 'young', 'medium', '', '2025-08-18 05:48:36', '2025-08-18 05:48:36'),
(80, 18, 'owley', 'dog', 'dog', 'african', 'young', 'medium', '', '2025-08-18 06:04:31', '2025-08-18 06:04:31'),
(81, 17, 'owley', 'dog', 'dog', 'african', 'young', 'large', 'None', '2025-08-18 06:05:43', '2025-08-18 06:05:43'),
(82, 17, 'Catcat', 'cat', 'cat', 'Munchkin', 'young', 'small', 'Cute and Aggressive ', '2025-08-18 09:23:18', '2025-08-18 09:23:18'),
(83, 17, 'Catcat', 'cat', 'cat', 'Munchkin', 'young', 'small', 'Cute and Aggressive ', '2025-08-18 09:23:21', '2025-08-18 09:23:21'),
(84, 17, 'Catcat', 'cat', 'cat', 'Munchkin', 'young', 'small', 'Cute and Aggressive ', '2025-08-18 09:23:28', '2025-08-18 09:23:28'),
(85, 17, 'Catcat', 'cat', 'cat', 'Munchkin', 'young', 'small', 'Cute and Aggressive ', '2025-08-18 09:23:28', '2025-08-18 09:23:28'),
(86, 17, 'owley', 'cat', 'cat', 'Aegean', 'young', 'small', '', '2025-08-18 09:42:25', '2025-08-18 09:42:25'),
(87, 17, 'owley', 'dog', 'dog', 'finnish', 'young', 'medium', 'none', '2025-08-18 10:23:37', '2025-08-18 10:23:37'),
(88, 17, 'owley', 'cat', 'cat', 'Abyssinian', 'adult', 'medium', 'none', '2025-08-18 10:26:35', '2025-08-18 10:26:35'),
(89, 17, 'owley', 'dog', 'dog', 'african', 'young', 'medium', 'none', '2025-08-18 10:29:20', '2025-08-18 10:29:20'),
(90, 18, 'owley', 'cat', 'cat', 'Birman', 'young', 'medium', '', '2025-08-18 10:36:54', '2025-08-18 10:36:54'),
(91, 17, 'owley', 'dog', 'dog', 'african', 'young', 'medium', '', '2025-08-18 10:50:40', '2025-08-18 10:50:40'),
(92, 17, 'tanggol', 'cat', 'cat', 'Aegean', 'young', 'medium', '', '2025-08-18 12:20:24', '2025-08-18 12:20:24'),
(93, 17, 'tanggol', 'cat', 'cat', 'Aegean', 'adult', 'medium', '', '2025-08-18 12:50:37', '2025-08-18 12:50:37'),
(94, 17, 'tanggol', 'cat', 'cat', 'Aegean', 'young', 'medium', '', '2025-08-18 13:08:06', '2025-08-18 13:08:06'),
(95, 17, 'owley', 'dog', 'dog', 'mudhol', 'young', 'small', '', '2025-08-18 17:20:47', '2025-08-18 17:20:47'),
(96, 17, 'owley', 'dog', 'dog', 'airedale', 'young', 'large', '', '2025-08-18 17:50:54', '2025-08-18 17:50:54'),
(97, 17, 'tanggol', 'dog', 'dog', 'african', 'young', 'small', '', '2025-08-18 17:57:47', '2025-08-18 17:57:47'),
(98, 18, 'owley', 'cat', 'cat', 'American Wirehair', 'young', 'medium', '', '2025-08-19 03:34:12', '2025-08-19 03:34:12'),
(99, 19, 'Ollie', 'cat', 'cat', 'Persian', 'young', 'medium', 'Aggressive', '2025-08-19 03:43:28', '2025-08-19 03:43:28'),
(100, 20, 'Pulot', 'dog', 'dog', 'labrador', 'young', 'medium', 'Cute', '2025-08-19 03:55:36', '2025-08-19 03:55:36'),
(101, 20, 'owley', 'dog', 'dog', 'airedale', 'young', 'small', '', '2025-08-19 04:12:24', '2025-08-19 04:12:24'),
(102, 17, 'tanggol', 'dog', 'dog', 'african', 'young', 'medium', '', '2025-08-19 04:15:56', '2025-08-19 04:15:56'),
(103, 21, 'tanggol', 'dog', 'dog', 'african', 'young', 'medium', 'cute', '2025-08-19 04:30:39', '2025-08-19 04:30:39'),
(104, 22, 'owley', 'cat', 'cat', 'Aegean', 'young', 'small', '', '2025-08-19 05:41:47', '2025-08-19 05:41:47'),
(105, 23, 'tanggol', 'dog', 'dog', 'african', 'young', 'large', '', '2025-08-19 05:53:04', '2025-08-19 05:53:04');

-- --------------------------------------------------------

--
-- Table structure for table `rfid_cards`
--

CREATE TABLE `rfid_cards` (
  `id` int(11) NOT NULL,
  `card_uid` varchar(50) NOT NULL,
  `custom_uid` varchar(8) NOT NULL,
  `firebase_doc_id` varchar(100) DEFAULT NULL,
  `tap_count` int(11) DEFAULT 1,
  `max_taps` int(11) DEFAULT 5,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_active` tinyint(1) DEFAULT 1,
  `last_firebase_sync` timestamp NULL DEFAULT NULL,
  `validation_time_ms` int(11) DEFAULT 3000,
  `device_source` varchar(50) DEFAULT 'ESP32-RFID-Scanner',
  `status` enum('active','expired','disabled') DEFAULT 'active'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `rfid_cards`
--

INSERT INTO `rfid_cards` (`id`, `card_uid`, `custom_uid`, `firebase_doc_id`, `tap_count`, `max_taps`, `created_at`, `updated_at`, `is_active`, `last_firebase_sync`, `validation_time_ms`, `device_source`, `status`) VALUES
(26, '73:77:f8:39', 'QXFEG1QQ', NULL, 2, 5, '2025-08-17 16:47:03', '2025-08-19 03:33:04', 1, '2025-08-19 03:33:04', 3000, 'ESP32-RFID-Scanner', 'active'),
(27, '4c:3f:b6:01', 'TU8A4I60', NULL, 5, 5, '2025-08-17 17:07:19', '2025-08-19 04:17:56', 1, '2025-08-19 04:17:56', 3000, 'ESP32-RFID-Scanner', 'active'),
(28, '53:89:08:02', 'DQOVZW0I', NULL, 5, 5, '2025-08-17 17:31:20', '2025-08-19 05:58:05', 1, '2025-08-19 05:58:05', 3000, 'ESP32-RFID-Scanner', 'active'),
(29, 'c2:48:94:ab', 'LJVLYGJB', NULL, 5, 5, '2025-08-17 17:33:29', '2025-08-19 04:18:33', 1, '2025-08-19 04:18:33', 3000, 'ESP32-RFID-Scanner', 'active'),
(30, '69:33:b2:01', '6UJKYDWX', NULL, 2, 5, '2025-08-17 18:12:10', '2025-08-19 03:30:34', 1, '2025-08-18 17:56:31', 3000, 'ESP32-RFID-Scanner', 'active'),
(31, '22:b0:8f:c3', 'XXFTZ825', NULL, 2, 5, '2025-08-18 03:35:44', '2025-08-19 03:30:34', 1, '2025-08-18 13:07:19', 3000, 'ESP32-RFID-Scanner', 'active'),
(32, '11:7b:b0:01', 'F7A6UHDQ', NULL, 2, 5, '2025-08-18 03:41:01', '2025-08-19 05:41:33', 1, '2025-08-19 05:41:33', 3000, 'ESP32-RFID-Scanner', 'active');

-- --------------------------------------------------------

--
-- Table structure for table `rfid_tags`
--

CREATE TABLE `rfid_tags` (
  `id` int(11) NOT NULL,
  `tag_id` varchar(20) NOT NULL,
  `pet_id` int(11) DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `assigned_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `rfid_tap_history`
--

CREATE TABLE `rfid_tap_history` (
  `id` int(11) NOT NULL,
  `rfid_card_id` int(11) DEFAULT NULL,
  `card_uid` varchar(50) NOT NULL,
  `custom_uid` varchar(8) NOT NULL,
  `tap_number` int(11) NOT NULL,
  `firebase_doc_id` varchar(100) DEFAULT NULL,
  `tapped_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `device_info` varchar(100) DEFAULT NULL,
  `wifi_network` varchar(100) DEFAULT NULL,
  `signal_strength` int(11) DEFAULT NULL,
  `validation_status` enum('approved','pending','failed') DEFAULT 'approved',
  `readable_time` varchar(50) DEFAULT NULL,
  `timestamp_value` timestamp NULL DEFAULT NULL,
  `rfid_scanner_status` varchar(20) DEFAULT 'OK',
  `project_id` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `rfid_tap_history`
--

INSERT INTO `rfid_tap_history` (`id`, `rfid_card_id`, `card_uid`, `custom_uid`, `tap_number`, `firebase_doc_id`, `tapped_at`, `device_info`, `wifi_network`, `signal_strength`, `validation_status`, `readable_time`, `timestamp_value`, `rfid_scanner_status`, `project_id`) VALUES
(63, 26, '73:77:f8:39', 'JQZ8S6NI', 3, NULL, '2025-08-17 16:47:03', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -80, 'approved', '2025-08-18 00:47:03', '2025-08-17 16:47:03', 'OK', NULL),
(64, 26, '73:77:f8:39', 'JQZ8S6NI', 4, NULL, '2025-08-17 16:47:13', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-18 00:47:13', '2025-08-17 16:47:13', 'OK', NULL),
(65, 26, '73:77:f8:39', '5TKVETUH', 1, NULL, '2025-08-17 16:47:23', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-18 00:47:23', '2025-08-17 16:47:23', 'OK', NULL),
(66, 26, '73:77:f8:39', '5TKVETUH', 2, NULL, '2025-08-17 17:06:42', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-18 01:06:42', '2025-08-17 17:06:42', 'OK', NULL),
(67, 27, '4c:3f:b6:01', '0IRFLZOI', 2, NULL, '2025-08-17 17:07:19', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-18 01:07:19', '2025-08-17 17:07:19', 'OK', NULL),
(68, 27, '4c:3f:b6:01', '0IRFLZOI', 3, NULL, '2025-08-17 17:07:30', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-18 01:07:31', '2025-08-17 17:07:31', 'OK', NULL),
(69, 27, '4c:3f:b6:01', '0IRFLZOI', 4, NULL, '2025-08-17 17:07:50', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-18 01:07:50', '2025-08-17 17:07:50', 'OK', NULL),
(70, 27, '4c:3f:b6:01', 'VQB5J7E7', 1, NULL, '2025-08-17 17:08:09', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -82, 'approved', '2025-08-18 01:08:09', '2025-08-17 17:08:09', 'OK', NULL),
(71, 28, '53:89:08:02', 'CDVV6DX5', 2, NULL, '2025-08-17 17:31:20', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -86, 'approved', '2025-08-18 01:31:20', '2025-08-17 17:31:20', 'OK', NULL),
(72, 28, '53:89:08:02', 'CDVV6DX5', 3, NULL, '2025-08-17 17:31:45', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-18 01:31:45', '2025-08-17 17:31:45', 'OK', NULL),
(73, 28, '53:89:08:02', 'CDVV6DX5', 4, NULL, '2025-08-17 17:31:55', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -79, 'approved', '2025-08-18 01:31:55', '2025-08-17 17:31:55', 'OK', NULL),
(74, 28, '53:89:08:02', 'U6DKP4UZ', 1, NULL, '2025-08-17 17:32:07', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -79, 'approved', '2025-08-18 01:32:07', '2025-08-17 17:32:07', 'OK', NULL),
(75, 29, 'c2:48:94:ab', 'N5926EOP', 2, NULL, '2025-08-17 17:33:29', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-18 01:33:29', '2025-08-17 17:33:29', 'OK', NULL),
(76, 29, 'c2:48:94:ab', 'N5926EOP', 3, NULL, '2025-08-17 17:33:39', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-18 01:33:39', '2025-08-17 17:33:39', 'OK', NULL),
(77, 29, 'c2:48:94:ab', 'N5926EOP', 4, NULL, '2025-08-17 17:33:53', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -79, 'approved', '2025-08-18 01:33:53', '2025-08-17 17:33:53', 'OK', NULL),
(78, 27, '4c:3f:b6:01', 'VQB5J7E7', 2, NULL, '2025-08-17 17:34:03', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -80, 'approved', '2025-08-18 01:34:03', '2025-08-17 17:34:03', 'OK', NULL),
(79, 29, 'c2:48:94:ab', '1HQCNMXF', 1, NULL, '2025-08-17 17:34:12', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-18 01:34:13', '2025-08-17 17:34:13', 'OK', NULL),
(80, 29, 'c2:48:94:ab', '1HQCNMXF', 2, NULL, '2025-08-17 18:03:18', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-18 02:03:18', '2025-08-17 18:03:18', 'OK', NULL),
(81, 29, 'c2:48:94:ab', '1HQCNMXF', 3, NULL, '2025-08-17 18:03:30', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -81, 'approved', '2025-08-18 02:03:30', '2025-08-17 18:03:30', 'OK', NULL),
(82, 29, 'c2:48:94:ab', '1HQCNMXF', 4, NULL, '2025-08-17 18:03:40', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -84, 'approved', '2025-08-18 02:03:40', '2025-08-17 18:03:40', 'OK', NULL),
(83, 29, 'c2:48:94:ab', '5QMJDTLZ', 1, NULL, '2025-08-17 18:03:49', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -79, 'approved', '2025-08-18 02:03:50', '2025-08-17 18:03:50', 'OK', NULL),
(84, 30, '69:33:b2:01', 'UAA83NON', 4, NULL, '2025-08-17 18:12:10', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-18 02:12:10', '2025-08-17 18:12:10', 'OK', NULL),
(85, 30, '69:33:b2:01', 'MLG7ZS6K', 1, NULL, '2025-08-17 18:12:19', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-18 02:12:20', '2025-08-17 18:12:20', 'OK', NULL),
(86, 30, '69:33:b2:01', 'MLG7ZS6K', 2, NULL, '2025-08-17 18:12:58', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-18 02:12:58', '2025-08-17 18:12:58', 'OK', NULL),
(87, 26, '73:77:f8:39', '5TKVETUH', 3, NULL, '2025-08-17 18:29:14', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-18 02:29:14', '2025-08-17 18:29:14', 'OK', NULL),
(88, 26, '73:77:f8:39', '5TKVETUH', 4, NULL, '2025-08-17 18:29:24', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-18 02:29:24', '2025-08-17 18:29:24', 'OK', NULL),
(89, 26, '73:77:f8:39', 'NPMCNGE5', 1, NULL, '2025-08-17 18:29:34', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-18 02:29:34', '2025-08-17 18:29:34', 'OK', NULL),
(90, 29, 'c2:48:94:ab', '5QMJDTLZ', 2, NULL, '2025-08-17 18:39:17', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-18 02:39:16', '2025-08-17 18:39:16', 'OK', NULL),
(91, 30, '69:33:b2:01', 'MLG7ZS6K', 3, NULL, '2025-08-17 18:41:03', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -85, 'approved', '2025-08-18 02:41:04', '2025-08-17 18:41:04', 'OK', NULL),
(92, 30, '69:33:b2:01', 'MLG7ZS6K', 4, NULL, '2025-08-17 18:41:13', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-18 02:41:13', '2025-08-17 18:41:13', 'OK', NULL),
(93, 30, '69:33:b2:01', '6KVLB5U4', 1, NULL, '2025-08-17 18:41:23', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-18 02:41:23', '2025-08-17 18:41:23', 'OK', NULL),
(94, 26, '73:77:f8:39', 'NPMCNGE5', 2, NULL, '2025-08-17 18:57:20', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-18 02:57:20', '2025-08-17 18:57:20', 'OK', NULL),
(95, 26, '73:77:f8:39', 'NPMCNGE5', 3, NULL, '2025-08-17 18:57:30', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-18 02:57:30', '2025-08-17 18:57:30', 'OK', NULL),
(96, 26, '73:77:f8:39', 'NPMCNGE5', 4, NULL, '2025-08-17 18:57:40', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -63, 'approved', '2025-08-18 02:57:40', '2025-08-17 18:57:40', 'OK', NULL),
(97, 26, '73:77:f8:39', 'FKRE30QH', 1, NULL, '2025-08-17 18:57:49', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-18 02:57:50', '2025-08-17 18:57:50', 'OK', NULL),
(98, 30, '69:33:b2:01', '6KVLB5U4', 2, NULL, '2025-08-17 19:01:21', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-18 03:01:21', '2025-08-17 19:01:21', 'OK', NULL),
(99, 30, '69:33:b2:01', '6KVLB5U4', 3, NULL, '2025-08-17 19:01:31', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-18 03:01:31', '2025-08-17 19:01:31', 'OK', NULL),
(100, 30, '69:33:b2:01', '6KVLB5U4', 4, NULL, '2025-08-17 19:01:41', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-18 03:01:41', '2025-08-17 19:01:41', 'OK', NULL),
(101, 30, '69:33:b2:01', 'EGM9UCJG', 1, NULL, '2025-08-17 19:01:50', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-18 03:01:50', '2025-08-17 19:01:50', 'OK', NULL),
(102, 28, '53:89:08:02', 'U6DKP4UZ', 2, NULL, '2025-08-17 19:05:12', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-18 03:05:12', '2025-08-17 19:05:12', 'OK', NULL),
(103, 28, '53:89:08:02', 'U6DKP4UZ', 3, NULL, '2025-08-17 19:05:21', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-18 03:05:22', '2025-08-17 19:05:22', 'OK', NULL),
(104, 28, '53:89:08:02', 'U6DKP4UZ', 4, NULL, '2025-08-17 19:05:34', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-18 03:05:34', '2025-08-17 19:05:34', 'OK', NULL),
(105, 28, '53:89:08:02', 'BK02IOXP', 1, NULL, '2025-08-17 19:05:44', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-18 03:05:44', '2025-08-17 19:05:44', 'OK', NULL),
(106, 29, 'c2:48:94:ab', '5QMJDTLZ', 3, NULL, '2025-08-17 19:09:57', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-18 03:09:57', '2025-08-17 19:09:57', 'OK', NULL),
(107, 29, 'c2:48:94:ab', '5QMJDTLZ', 4, NULL, '2025-08-17 19:10:07', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-18 03:10:07', '2025-08-17 19:10:07', 'OK', NULL),
(108, 29, 'c2:48:94:ab', 'CWGLF50P', 1, NULL, '2025-08-17 19:10:17', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-18 03:10:17', '2025-08-17 19:10:17', 'OK', NULL),
(109, 31, '22:b0:8f:c3', 'ZMBHIM9S', 2, NULL, '2025-08-18 03:35:44', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-18 11:35:49', '2025-08-18 03:35:49', 'OK', NULL),
(110, 31, '22:b0:8f:c3', 'ZMBHIM9S', 3, NULL, '2025-08-18 03:35:54', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -65, 'approved', '2025-08-18 11:35:58', '2025-08-18 03:35:58', 'OK', NULL),
(111, 31, '22:b0:8f:c3', 'ZMBHIM9S', 4, NULL, '2025-08-18 03:36:04', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -64, 'approved', '2025-08-18 11:36:08', '2025-08-18 03:36:08', 'OK', NULL),
(112, 31, '22:b0:8f:c3', 'TBAXNIWH', 1, NULL, '2025-08-18 03:36:14', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -66, 'approved', '2025-08-18 11:36:18', '2025-08-18 03:36:18', 'OK', NULL),
(113, 32, '11:7b:b0:01', 'KLHNUIT1', 1, NULL, '2025-08-18 03:41:01', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -78, 'approved', '2025-08-18 11:41:05', '2025-08-18 03:41:05', 'OK', NULL),
(114, 26, '73:77:f8:39', 'FKRE30QH', 2, NULL, '2025-08-18 03:45:34', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-18 11:45:38', '2025-08-18 03:45:38', 'OK', NULL),
(115, 26, '73:77:f8:39', 'FKRE30QH', 3, NULL, '2025-08-18 03:45:43', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-18 11:45:48', '2025-08-18 03:45:48', 'OK', NULL),
(116, 26, '73:77:f8:39', 'FKRE30QH', 4, NULL, '2025-08-18 03:45:53', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-18 11:45:57', '2025-08-18 03:45:57', 'OK', NULL),
(117, 26, '73:77:f8:39', '3ZWM7N2Z', 1, NULL, '2025-08-18 03:46:03', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-18 11:46:07', '2025-08-18 03:46:07', 'OK', NULL),
(118, 26, '73:77:f8:39', '3ZWM7N2Z', 2, NULL, '2025-08-18 04:36:49', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 00:40:29', '2025-08-16 16:40:29', 'OK', NULL),
(119, 26, '73:77:f8:39', '3ZWM7N2Z', 3, NULL, '2025-08-18 04:36:58', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-17 00:40:39', '2025-08-16 16:40:39', 'OK', NULL),
(120, 26, '73:77:f8:39', '3ZWM7N2Z', 4, NULL, '2025-08-18 04:37:08', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -79, 'approved', '2025-08-17 00:40:49', '2025-08-16 16:40:49', 'OK', NULL),
(121, 26, '73:77:f8:39', 'BKEP0GSH', 1, NULL, '2025-08-18 04:37:18', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -85, 'approved', '2025-08-17 00:40:59', '2025-08-16 16:40:59', 'OK', NULL),
(122, 29, 'c2:48:94:ab', 'CWGLF50P', 2, NULL, '2025-08-18 04:42:57', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 00:46:38', '2025-08-16 16:46:38', 'OK', NULL),
(123, 29, 'c2:48:94:ab', 'CWGLF50P', 3, NULL, '2025-08-18 04:43:07', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-17 00:46:48', '2025-08-16 16:46:48', 'OK', NULL),
(124, 29, 'c2:48:94:ab', 'CWGLF50P', 4, NULL, '2025-08-18 04:43:17', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 00:46:58', '2025-08-16 16:46:58', 'OK', NULL),
(125, 29, 'c2:48:94:ab', '3XI4R1M2', 1, NULL, '2025-08-18 04:43:28', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-17 00:47:08', '2025-08-16 16:47:08', 'OK', NULL),
(126, 31, '22:b0:8f:c3', 'TBAXNIWH', 2, NULL, '2025-08-18 05:18:48', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 01:22:29', '2025-08-16 17:22:29', 'OK', NULL),
(127, 31, '22:b0:8f:c3', 'TBAXNIWH', 3, NULL, '2025-08-18 05:18:58', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 01:22:39', '2025-08-16 17:22:39', 'OK', NULL),
(128, 31, '22:b0:8f:c3', 'TBAXNIWH', 4, NULL, '2025-08-18 05:19:08', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -78, 'approved', '2025-08-17 01:22:49', '2025-08-16 17:22:49', 'OK', NULL),
(129, 31, '22:b0:8f:c3', 'W7WV38JR', 1, NULL, '2025-08-18 05:19:18', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -82, 'approved', '2025-08-17 01:22:59', '2025-08-16 17:22:59', 'OK', NULL),
(130, 27, '4c:3f:b6:01', 'VQB5J7E7', 3, NULL, '2025-08-18 05:23:51', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -79, 'approved', '2025-08-17 01:27:31', '2025-08-16 17:27:31', 'OK', NULL),
(131, 27, '4c:3f:b6:01', 'VQB5J7E7', 4, NULL, '2025-08-18 05:24:00', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -80, 'approved', '2025-08-17 01:27:41', '2025-08-16 17:27:41', 'OK', NULL),
(132, 27, '4c:3f:b6:01', 'QWOU8RIT', 1, NULL, '2025-08-18 05:24:10', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -82, 'approved', '2025-08-17 01:27:51', '2025-08-16 17:27:51', 'OK', NULL),
(133, 30, '69:33:b2:01', 'EGM9UCJG', 2, NULL, '2025-08-18 05:25:52', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 01:29:28', '2025-08-16 17:29:28', 'OK', NULL),
(134, 30, '69:33:b2:01', 'EGM9UCJG', 3, NULL, '2025-08-18 05:26:01', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-17 01:29:38', '2025-08-16 17:29:38', 'OK', NULL),
(135, 30, '69:33:b2:01', 'EGM9UCJG', 4, NULL, '2025-08-18 05:26:11', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-17 01:29:48', '2025-08-16 17:29:48', 'OK', NULL),
(136, 30, '69:33:b2:01', 'PHOX6NAW', 1, NULL, '2025-08-18 05:26:21', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-17 01:29:58', '2025-08-16 17:29:58', 'OK', NULL),
(137, 28, '53:89:08:02', 'BK02IOXP', 2, NULL, '2025-08-18 05:37:42', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 01:41:19', '2025-08-16 17:41:19', 'OK', NULL),
(138, 28, '53:89:08:02', 'BK02IOXP', 3, NULL, '2025-08-18 05:37:52', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 01:41:28', '2025-08-16 17:41:28', 'OK', NULL),
(139, 28, '53:89:08:02', 'BK02IOXP', 4, NULL, '2025-08-18 05:38:02', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 01:41:38', '2025-08-16 17:41:38', 'OK', NULL),
(140, 28, '53:89:08:02', 'NTY2EYHS', 1, NULL, '2025-08-18 05:38:11', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 01:41:48', '2025-08-16 17:41:48', 'OK', NULL),
(141, 28, '53:89:08:02', 'NTY2EYHS', 2, NULL, '2025-08-18 05:41:46', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -88, 'approved', '2025-08-17 01:45:23', '2025-08-16 17:45:23', 'OK', NULL),
(142, 28, '53:89:08:02', 'NTY2EYHS', 3, NULL, '2025-08-18 05:41:56', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 01:45:32', '2025-08-16 17:45:32', 'OK', NULL),
(143, 28, '53:89:08:02', 'NTY2EYHS', 4, NULL, '2025-08-18 05:42:06', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -78, 'approved', '2025-08-17 01:45:42', '2025-08-16 17:45:42', 'OK', NULL),
(144, 28, '53:89:08:02', 'DPHJS82Z', 1, NULL, '2025-08-18 05:42:15', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 01:45:52', '2025-08-16 17:45:52', 'OK', NULL),
(145, 30, '69:33:b2:01', 'PHOX6NAW', 2, NULL, '2025-08-18 05:47:41', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 01:51:18', '2025-08-16 17:51:18', 'OK', NULL),
(146, 30, '69:33:b2:01', 'PHOX6NAW', 3, NULL, '2025-08-18 05:47:51', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 01:51:28', '2025-08-16 17:51:28', 'OK', NULL),
(147, 30, '69:33:b2:01', 'PHOX6NAW', 4, NULL, '2025-08-18 05:48:01', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 01:51:37', '2025-08-16 17:51:37', 'OK', NULL),
(148, 30, '69:33:b2:01', 'XP29VP42', 1, NULL, '2025-08-18 05:48:11', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 01:51:47', '2025-08-16 17:51:47', 'OK', NULL),
(149, 26, '73:77:f8:39', 'BKEP0GSH', 2, NULL, '2025-08-18 06:00:42', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 02:04:18', '2025-08-16 18:04:18', 'OK', NULL),
(150, 26, '73:77:f8:39', 'BKEP0GSH', 3, NULL, '2025-08-18 06:00:52', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-17 02:04:28', '2025-08-16 18:04:28', 'OK', NULL),
(151, 26, '73:77:f8:39', 'BKEP0GSH', 4, NULL, '2025-08-18 06:01:02', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 02:04:38', '2025-08-16 18:04:38', 'OK', NULL),
(152, 26, '73:77:f8:39', '313IW8SK', 1, NULL, '2025-08-18 06:01:11', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-17 02:04:48', '2025-08-16 18:04:48', 'OK', NULL),
(153, 29, 'c2:48:94:ab', '3XI4R1M2', 2, NULL, '2025-08-18 06:05:09', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 02:08:46', '2025-08-16 18:08:46', 'OK', NULL),
(154, 29, 'c2:48:94:ab', '3XI4R1M2', 3, NULL, '2025-08-18 06:05:19', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 02:08:56', '2025-08-16 18:08:56', 'OK', NULL),
(155, 29, 'c2:48:94:ab', '3XI4R1M2', 4, NULL, '2025-08-18 06:05:29', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 02:09:05', '2025-08-16 18:09:05', 'OK', NULL),
(156, 29, 'c2:48:94:ab', 'SU47TXJ9', 1, NULL, '2025-08-18 06:05:39', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 02:09:15', '2025-08-16 18:09:15', 'OK', NULL),
(157, 26, '73:77:f8:39', '313IW8SK', 2, NULL, '2025-08-18 09:22:43', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -66, 'approved', '2025-08-17 05:26:21', '2025-08-16 21:26:21', 'OK', NULL),
(158, 26, '73:77:f8:39', '313IW8SK', 3, NULL, '2025-08-18 09:22:54', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -65, 'approved', '2025-08-17 05:26:31', '2025-08-16 21:26:31', 'OK', NULL),
(159, 26, '73:77:f8:39', '313IW8SK', 4, NULL, '2025-08-18 09:23:03', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-17 05:26:41', '2025-08-16 21:26:41', 'OK', NULL),
(160, 26, '73:77:f8:39', '3A7YRMAL', 1, NULL, '2025-08-18 09:23:13', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-17 05:26:50', '2025-08-16 21:26:50', 'OK', NULL),
(161, 29, 'c2:48:94:ab', 'SU47TXJ9', 2, NULL, '2025-08-18 09:32:55', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-17 05:36:32', '2025-08-16 21:36:32', 'OK', NULL),
(162, 29, 'c2:48:94:ab', 'SU47TXJ9', 3, NULL, '2025-08-18 09:33:05', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -78, 'approved', '2025-08-17 05:36:42', '2025-08-16 21:36:42', 'OK', NULL),
(163, 29, 'c2:48:94:ab', 'SU47TXJ9', 4, NULL, '2025-08-18 09:33:15', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 05:36:52', '2025-08-16 21:36:52', 'OK', NULL),
(164, 29, 'c2:48:94:ab', 'A18WIJFW', 1, NULL, '2025-08-18 09:33:27', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 05:37:04', '2025-08-16 21:37:04', 'OK', NULL),
(165, 32, '11:7b:b0:01', 'KLHNUIT1', 2, NULL, '2025-08-18 10:23:03', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 06:26:40', '2025-08-16 22:26:40', 'OK', NULL),
(166, 32, '11:7b:b0:01', 'KLHNUIT1', 3, NULL, '2025-08-18 10:23:13', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 06:26:50', '2025-08-16 22:26:50', 'OK', NULL),
(167, 32, '11:7b:b0:01', 'KLHNUIT1', 4, NULL, '2025-08-18 10:23:23', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-17 06:27:00', '2025-08-16 22:27:00', 'OK', NULL),
(168, 32, '11:7b:b0:01', 'UUVNMQRS', 1, NULL, '2025-08-18 10:23:33', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-17 06:27:10', '2025-08-16 22:27:10', 'OK', NULL),
(169, 27, '4c:3f:b6:01', 'QWOU8RIT', 2, NULL, '2025-08-18 10:26:02', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 06:29:39', '2025-08-16 22:29:39', 'OK', NULL),
(170, 27, '4c:3f:b6:01', 'QWOU8RIT', 3, NULL, '2025-08-18 10:26:12', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 06:29:49', '2025-08-16 22:29:49', 'OK', NULL),
(171, 27, '4c:3f:b6:01', 'QWOU8RIT', 4, NULL, '2025-08-18 10:26:22', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 06:29:59', '2025-08-16 22:29:59', 'OK', NULL),
(172, 27, '4c:3f:b6:01', 'MLG7ZS6K', 1, NULL, '2025-08-18 10:26:32', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 06:30:09', '2025-08-16 22:30:09', 'OK', NULL),
(173, 28, '53:89:08:02', 'DPHJS82Z', 2, NULL, '2025-08-18 10:28:47', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 06:32:24', '2025-08-16 22:32:24', 'OK', NULL),
(174, 28, '53:89:08:02', 'DPHJS82Z', 3, NULL, '2025-08-18 10:28:57', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -76, 'approved', '2025-08-17 06:32:34', '2025-08-16 22:32:34', 'OK', NULL),
(175, 28, '53:89:08:02', 'DPHJS82Z', 4, NULL, '2025-08-18 10:29:06', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -76, 'approved', '2025-08-17 06:32:44', '2025-08-16 22:32:44', 'OK', NULL),
(176, 28, '53:89:08:02', '46NWEJPB', 1, NULL, '2025-08-18 10:29:16', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -81, 'approved', '2025-08-17 06:32:54', '2025-08-16 22:32:54', 'OK', NULL),
(177, 26, '73:77:f8:39', '3A7YRMAL', 2, NULL, '2025-08-18 10:36:20', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-17 06:39:57', '2025-08-16 22:39:57', 'OK', NULL),
(178, 26, '73:77:f8:39', '3A7YRMAL', 3, NULL, '2025-08-18 10:36:30', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 06:40:07', '2025-08-16 22:40:07', 'OK', NULL),
(179, 26, '73:77:f8:39', '3A7YRMAL', 4, NULL, '2025-08-18 10:36:39', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -80, 'approved', '2025-08-17 06:40:17', '2025-08-16 22:40:17', 'OK', NULL),
(180, 26, '73:77:f8:39', 'A3ESN3KH', 1, NULL, '2025-08-18 10:36:49', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 06:40:27', '2025-08-16 22:40:27', 'OK', NULL),
(181, 26, '73:77:f8:39', 'A3ESN3KH', 2, NULL, '2025-08-18 10:50:07', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -65, 'approved', '2025-08-17 06:53:45', '2025-08-16 22:53:45', 'OK', NULL),
(182, 26, '73:77:f8:39', 'A3ESN3KH', 3, NULL, '2025-08-18 10:50:17', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -66, 'approved', '2025-08-17 06:53:55', '2025-08-16 22:53:55', 'OK', NULL),
(183, 26, '73:77:f8:39', 'A3ESN3KH', 4, NULL, '2025-08-18 10:50:27', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -66, 'approved', '2025-08-17 06:54:04', '2025-08-16 22:54:04', 'OK', NULL),
(184, 26, '73:77:f8:39', 'CUPYNJS1', 1, NULL, '2025-08-18 10:50:37', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 06:54:14', '2025-08-16 22:54:14', 'OK', NULL),
(185, 31, '22:b0:8f:c3', 'W7WV38JR', 2, NULL, '2025-08-18 12:19:48', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -66, 'approved', '2025-08-17 08:23:25', '2025-08-17 00:23:25', 'OK', NULL),
(186, 31, '22:b0:8f:c3', 'W7WV38JR', 3, NULL, '2025-08-18 12:19:58', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -64, 'approved', '2025-08-17 08:23:35', '2025-08-17 00:23:35', 'OK', NULL),
(187, 31, '22:b0:8f:c3', 'W7WV38JR', 4, NULL, '2025-08-18 12:20:08', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -63, 'approved', '2025-08-17 08:23:45', '2025-08-17 00:23:45', 'OK', NULL),
(188, 31, '22:b0:8f:c3', '3ZJZPV7R', 1, NULL, '2025-08-18 12:20:17', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 08:23:55', '2025-08-17 00:23:55', 'OK', NULL),
(189, 31, '22:b0:8f:c3', '3ZJZPV7R', 2, NULL, '2025-08-18 12:25:45', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 08:29:22', '2025-08-17 00:29:22', 'OK', NULL),
(190, 31, '22:b0:8f:c3', '3ZJZPV7R', 3, NULL, '2025-08-18 12:26:39', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 08:30:17', '2025-08-17 00:30:17', 'OK', NULL),
(191, 31, '22:b0:8f:c3', '3ZJZPV7R', 4, NULL, '2025-08-18 12:26:49', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -63, 'approved', '2025-08-17 08:30:27', '2025-08-17 00:30:27', 'OK', NULL),
(192, 31, '22:b0:8f:c3', 'S5FZDXRU', 1, NULL, '2025-08-18 12:48:12', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-17 08:51:50', '2025-08-17 00:51:50', 'OK', NULL),
(193, 31, '22:b0:8f:c3', 'S5FZDXRU', 2, NULL, '2025-08-18 12:48:22', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-17 08:51:59', '2025-08-17 00:51:59', 'OK', NULL),
(194, 31, '22:b0:8f:c3', 'S5FZDXRU', 3, NULL, '2025-08-18 12:48:32', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -64, 'approved', '2025-08-17 08:52:09', '2025-08-17 00:52:09', 'OK', NULL),
(195, 31, '22:b0:8f:c3', 'S5FZDXRU', 4, NULL, '2025-08-18 12:48:41', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -64, 'approved', '2025-08-17 08:52:19', '2025-08-17 00:52:19', 'OK', NULL),
(196, 31, '22:b0:8f:c3', 'OAS5V4CN', 1, NULL, '2025-08-18 12:48:51', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 08:52:29', '2025-08-17 00:52:29', 'OK', NULL),
(197, 31, '22:b0:8f:c3', 'OAS5V4CN', 2, NULL, '2025-08-18 12:49:04', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -60, 'approved', '2025-08-17 08:52:42', '2025-08-17 00:52:42', 'OK', NULL),
(198, 31, '22:b0:8f:c3', 'OAS5V4CN', 3, NULL, '2025-08-18 12:49:14', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -65, 'approved', '2025-08-17 08:52:51', '2025-08-17 00:52:51', 'OK', NULL),
(199, 31, '22:b0:8f:c3', 'OAS5V4CN', 4, NULL, '2025-08-18 12:49:24', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -64, 'approved', '2025-08-17 08:53:01', '2025-08-17 00:53:01', 'OK', NULL),
(200, 31, '22:b0:8f:c3', 'L4VX57DB', 1, NULL, '2025-08-18 12:49:33', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -65, 'approved', '2025-08-17 08:53:11', '2025-08-17 00:53:11', 'OK', NULL),
(201, 26, '73:77:f8:39', 'CUPYNJS1', 2, NULL, '2025-08-18 12:50:02', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 08:53:40', '2025-08-17 00:53:40', 'OK', NULL),
(202, 26, '73:77:f8:39', 'CUPYNJS1', 3, NULL, '2025-08-18 12:50:12', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-17 08:53:50', '2025-08-17 00:53:50', 'OK', NULL),
(203, 26, '73:77:f8:39', 'CUPYNJS1', 4, NULL, '2025-08-18 12:50:22', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 08:53:59', '2025-08-17 00:53:59', 'OK', NULL),
(204, 26, '73:77:f8:39', 'MHB2Q4YI', 1, NULL, '2025-08-18 12:50:32', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 08:54:09', '2025-08-17 00:54:09', 'OK', NULL),
(205, 31, '22:b0:8f:c3', 'L4VX57DB', 2, NULL, '2025-08-18 13:06:40', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-17 09:10:17', '2025-08-17 01:10:17', 'OK', NULL),
(206, 31, '22:b0:8f:c3', 'L4VX57DB', 3, NULL, '2025-08-18 13:06:50', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 09:10:27', '2025-08-17 01:10:27', 'OK', NULL),
(207, 31, '22:b0:8f:c3', 'L4VX57DB', 4, NULL, '2025-08-18 13:07:00', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-17 09:10:37', '2025-08-17 01:10:37', 'OK', NULL),
(208, 31, '22:b0:8f:c3', 'XXFTZ825', 1, NULL, '2025-08-18 13:07:09', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-17 09:10:47', '2025-08-17 01:10:47', 'OK', NULL),
(209, 31, '22:b0:8f:c3', 'XXFTZ825', 2, NULL, '2025-08-18 13:07:19', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 09:10:57', '2025-08-17 01:10:57', 'OK', NULL),
(210, 26, '73:77:f8:39', 'MHB2Q4YI', 2, NULL, '2025-08-18 13:07:30', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 09:11:08', '2025-08-17 01:11:08', 'OK', NULL),
(211, 26, '73:77:f8:39', 'MHB2Q4YI', 3, NULL, '2025-08-18 13:07:40', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 09:11:18', '2025-08-17 01:11:18', 'OK', NULL),
(212, 26, '73:77:f8:39', 'MHB2Q4YI', 4, NULL, '2025-08-18 13:07:50', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 09:11:27', '2025-08-17 01:11:27', 'OK', NULL),
(213, 26, '73:77:f8:39', '7L1YIT8M', 1, NULL, '2025-08-18 13:07:59', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -79, 'approved', '2025-08-17 09:11:37', '2025-08-17 01:11:37', 'OK', NULL),
(214, 26, '73:77:f8:39', '7L1YIT8M', 2, NULL, '2025-08-18 13:14:18', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 09:17:56', '2025-08-17 01:17:56', 'OK', NULL),
(215, 26, '73:77:f8:39', '7L1YIT8M', 3, NULL, '2025-08-18 13:18:06', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-17 09:21:44', '2025-08-17 01:21:44', 'OK', NULL),
(216, 26, '73:77:f8:39', '7L1YIT8M', 4, NULL, '2025-08-18 13:18:25', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -78, 'approved', '2025-08-17 09:22:03', '2025-08-17 01:22:03', 'OK', NULL),
(217, 26, '73:77:f8:39', 'L5OFL9U8', 1, NULL, '2025-08-18 13:18:39', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -85, 'approved', '2025-08-17 09:22:17', '2025-08-17 01:22:17', 'OK', NULL),
(218, 26, '73:77:f8:39', 'L5OFL9U8', 2, NULL, '2025-08-18 17:19:24', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 13:23:02', '2025-08-17 05:23:02', 'OK', NULL),
(219, 26, '73:77:f8:39', 'L5OFL9U8', 3, NULL, '2025-08-18 17:19:34', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 13:23:12', '2025-08-17 05:23:12', 'OK', NULL),
(220, 26, '73:77:f8:39', 'L5OFL9U8', 4, NULL, '2025-08-18 17:19:44', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 13:23:22', '2025-08-17 05:23:22', 'OK', NULL),
(221, 26, '73:77:f8:39', 'BVP14G03', 1, NULL, '2025-08-18 17:19:53', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 13:23:32', '2025-08-17 05:23:32', 'OK', NULL),
(222, 26, '73:77:f8:39', 'BVP14G03', 2, NULL, '2025-08-18 17:20:04', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -78, 'approved', '2025-08-17 13:23:43', '2025-08-17 05:23:43', 'OK', NULL),
(223, 30, '69:33:b2:01', 'XP29VP42', 2, NULL, '2025-08-18 17:20:14', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -78, 'approved', '2025-08-17 13:23:52', '2025-08-17 05:23:52', 'OK', NULL),
(224, 30, '69:33:b2:01', 'XP29VP42', 3, NULL, '2025-08-18 17:20:24', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -79, 'approved', '2025-08-17 13:24:02', '2025-08-17 05:24:02', 'OK', NULL),
(225, 30, '69:33:b2:01', 'XP29VP42', 4, NULL, '2025-08-18 17:20:33', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -78, 'approved', '2025-08-17 13:24:12', '2025-08-17 05:24:12', 'OK', NULL),
(226, 30, '69:33:b2:01', 'I0YCJQDQ', 1, NULL, '2025-08-18 17:20:43', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-17 13:24:21', '2025-08-17 05:24:21', 'OK', NULL),
(227, 30, '69:33:b2:01', 'I0YCJQDQ', 2, NULL, '2025-08-18 17:21:23', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -76, 'approved', '2025-08-17 13:25:01', '2025-08-17 05:25:01', 'OK', NULL),
(228, 30, '69:33:b2:01', 'I0YCJQDQ', 3, NULL, '2025-08-18 17:21:37', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-17 13:25:15', '2025-08-17 05:25:15', 'OK', NULL),
(229, 30, '69:33:b2:01', 'I0YCJQDQ', 4, NULL, '2025-08-18 17:21:50', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -80, 'approved', '2025-08-17 13:25:28', '2025-08-17 05:25:28', 'OK', NULL),
(230, 30, '69:33:b2:01', '1Q1P2B44', 1, NULL, '2025-08-18 17:50:50', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-17 13:54:33', '2025-08-17 05:54:33', 'OK', NULL),
(231, 30, '69:33:b2:01', '1Q1P2B44', 2, NULL, '2025-08-18 17:51:41', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 13:55:23', '2025-08-17 05:55:23', 'OK', NULL),
(232, 30, '69:33:b2:01', '1Q1P2B44', 3, NULL, '2025-08-18 17:52:13', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 13:55:56', '2025-08-17 05:55:56', 'OK', NULL),
(233, 30, '69:33:b2:01', '1Q1P2B44', 4, NULL, '2025-08-18 17:52:27', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 13:56:09', '2025-08-17 05:56:09', 'OK', NULL),
(234, 30, '69:33:b2:01', '3QZUNIEI', 1, NULL, '2025-08-18 17:53:15', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 13:56:57', '2025-08-17 05:56:57', 'OK', NULL),
(235, 30, '69:33:b2:01', '3QZUNIEI', 2, NULL, '2025-08-18 17:53:46', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-17 13:57:28', '2025-08-17 05:57:28', 'OK', NULL),
(236, 30, '69:33:b2:01', '3QZUNIEI', 3, NULL, '2025-08-18 17:54:34', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 13:58:17', '2025-08-17 05:58:17', 'OK', NULL),
(237, 30, '69:33:b2:01', '3QZUNIEI', 4, NULL, '2025-08-18 17:54:44', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-17 13:58:26', '2025-08-17 05:58:26', 'OK', NULL),
(238, 30, '69:33:b2:01', 'SPJP6ELO', 1, NULL, '2025-08-18 17:54:58', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 13:58:40', '2025-08-17 05:58:40', 'OK', NULL),
(239, 30, '69:33:b2:01', 'SPJP6ELO', 2, NULL, '2025-08-18 17:55:50', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 13:59:33', '2025-08-17 05:59:33', 'OK', NULL),
(240, 30, '69:33:b2:01', 'SPJP6ELO', 3, NULL, '2025-08-18 17:56:00', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 13:59:42', '2025-08-17 05:59:42', 'OK', NULL),
(241, 30, '69:33:b2:01', 'SPJP6ELO', 4, NULL, '2025-08-18 17:56:10', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 13:59:52', '2025-08-17 05:59:52', 'OK', NULL),
(242, 30, '69:33:b2:01', '6UJKYDWX', 1, NULL, '2025-08-18 17:56:20', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 14:00:02', '2025-08-17 06:00:02', 'OK', NULL),
(243, 30, '69:33:b2:01', '6UJKYDWX', 2, NULL, '2025-08-18 17:56:31', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 14:00:13', '2025-08-17 06:00:13', 'OK', NULL),
(244, 32, '11:7b:b0:01', 'UUVNMQRS', 2, NULL, '2025-08-18 17:56:42', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -76, 'approved', '2025-08-17 14:00:24', '2025-08-17 06:00:24', 'OK', NULL),
(245, 32, '11:7b:b0:01', 'UUVNMQRS', 3, NULL, '2025-08-18 17:56:56', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-17 14:00:38', '2025-08-17 06:00:38', 'OK', NULL),
(246, 32, '11:7b:b0:01', 'UUVNMQRS', 4, NULL, '2025-08-18 17:57:05', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 14:00:48', '2025-08-17 06:00:48', 'OK', NULL),
(247, 32, '11:7b:b0:01', 'X0DL0PCN', 1, NULL, '2025-08-18 17:57:15', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-17 14:00:58', '2025-08-17 06:00:58', 'OK', NULL),
(248, 32, '11:7b:b0:01', 'X0DL0PCN', 2, NULL, '2025-08-18 17:58:17', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-17 14:02:00', '2025-08-17 06:02:00', 'OK', NULL),
(249, 32, '11:7b:b0:01', 'X0DL0PCN', 3, NULL, '2025-08-18 17:58:32', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -65, 'approved', '2025-08-17 14:02:15', '2025-08-17 06:02:15', 'OK', NULL),
(250, 32, '11:7b:b0:01', 'X0DL0PCN', 4, NULL, '2025-08-18 17:58:46', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-17 14:02:29', '2025-08-17 06:02:29', 'OK', NULL),
(251, 32, '11:7b:b0:01', '9UAWJ9PP', 1, NULL, '2025-08-18 17:59:00', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-17 14:02:43', '2025-08-17 06:02:43', 'OK', NULL),
(252, 32, '11:7b:b0:01', '9UAWJ9PP', 2, NULL, '2025-08-18 17:59:32', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 14:03:14', '2025-08-17 06:03:14', 'OK', NULL),
(253, 26, '73:77:f8:39', 'BVP14G03', 3, NULL, '2025-08-19 02:53:49', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-17 00:34:53', '2025-08-16 16:34:53', 'OK', NULL),
(254, 32, '11:7b:b0:01', '9UAWJ9PP', 3, NULL, '2025-08-19 02:54:07', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-17 00:35:11', '2025-08-16 16:35:11', 'OK', NULL),
(255, 26, '73:77:f8:39', 'BVP14G03', 4, NULL, '2025-08-19 03:32:35', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 11:32:35', '2025-08-19 03:32:35', 'OK', NULL),
(256, 26, '73:77:f8:39', 'BVP14G03', 5, NULL, '2025-08-19 03:32:45', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-19 11:32:45', '2025-08-19 03:32:45', 'OK', NULL),
(257, 26, '73:77:f8:39', 'QXFEG1QQ', 1, NULL, '2025-08-19 03:32:55', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-19 11:32:55', '2025-08-19 03:32:55', 'OK', NULL),
(258, 26, '73:77:f8:39', 'QXFEG1QQ', 2, NULL, '2025-08-19 03:33:04', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-19 11:33:04', '2025-08-19 03:33:04', 'OK', NULL),
(259, 28, '53:89:08:02', '46NWEJPB', 2, NULL, '2025-08-19 03:33:22', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -66, 'approved', '2025-08-19 11:33:22', '2025-08-19 03:33:22', 'OK', NULL),
(260, 28, '53:89:08:02', '46NWEJPB', 3, NULL, '2025-08-19 03:33:36', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 11:33:36', '2025-08-19 03:33:36', 'OK', NULL),
(261, 28, '53:89:08:02', '46NWEJPB', 4, NULL, '2025-08-19 03:33:46', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-19 11:33:46', '2025-08-19 03:33:46', 'OK', NULL),
(262, 28, '53:89:08:02', '46NWEJPB', 5, NULL, '2025-08-19 03:33:56', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-19 11:33:56', '2025-08-19 03:33:56', 'OK', NULL),
(263, 28, '53:89:08:02', '5OCP6XFN', 1, NULL, '2025-08-19 03:34:06', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-19 11:34:06', '2025-08-19 03:34:06', 'OK', NULL),
(264, 28, '53:89:08:02', '5OCP6XFN', 2, NULL, '2025-08-19 03:34:40', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-19 11:34:40', '2025-08-19 03:34:40', 'OK', NULL),
(265, 28, '53:89:08:02', '5OCP6XFN', 3, NULL, '2025-08-19 03:35:29', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-19 11:35:29', '2025-08-19 03:35:29', 'OK', NULL),
(266, 28, '53:89:08:02', '5OCP6XFN', 4, NULL, '2025-08-19 03:35:48', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-19 11:35:48', '2025-08-19 03:35:48', 'OK', NULL),
(267, 28, '53:89:08:02', '5OCP6XFN', 5, NULL, '2025-08-19 03:36:07', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-19 11:36:07', '2025-08-19 03:36:07', 'OK', NULL),
(268, 28, '53:89:08:02', 'I4OPS0V5', 1, NULL, '2025-08-19 03:43:25', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -83, 'approved', '2025-08-19 11:43:25', '2025-08-19 03:43:25', 'OK', NULL),
(269, 28, '53:89:08:02', 'I4OPS0V5', 2, NULL, '2025-08-19 03:43:53', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -80, 'approved', '2025-08-19 11:43:53', '2025-08-19 03:43:53', 'OK', NULL),
(270, 28, '53:89:08:02', 'I4OPS0V5', 3, NULL, '2025-08-19 03:44:06', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-19 11:44:06', '2025-08-19 03:44:06', 'OK', NULL),
(271, 28, '53:89:08:02', 'I4OPS0V5', 4, NULL, '2025-08-19 03:44:26', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-19 11:44:26', '2025-08-19 03:44:26', 'OK', NULL),
(272, 28, '53:89:08:02', 'I4OPS0V5', 5, NULL, '2025-08-19 03:44:45', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-19 11:44:45', '2025-08-19 03:44:45', 'OK', NULL),
(273, 28, '53:89:08:02', 'V06LWCWV', 1, NULL, '2025-08-19 03:55:33', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-19 11:55:33', '2025-08-19 03:55:33', 'OK', NULL),
(274, 28, '53:89:08:02', 'V06LWCWV', 2, NULL, '2025-08-19 03:56:13', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-19 11:56:13', '2025-08-19 03:56:13', 'OK', NULL),
(275, 28, '53:89:08:02', 'V06LWCWV', 3, NULL, '2025-08-19 03:56:28', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -76, 'approved', '2025-08-19 11:56:28', '2025-08-19 03:56:28', 'OK', NULL),
(276, 28, '53:89:08:02', 'V06LWCWV', 4, NULL, '2025-08-19 03:56:48', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -77, 'approved', '2025-08-19 11:56:48', '2025-08-19 03:56:48', 'OK', NULL),
(277, 28, '53:89:08:02', 'V06LWCWV', 5, NULL, '2025-08-19 03:57:08', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-19 11:57:07', '2025-08-19 03:57:07', 'OK', NULL),
(278, 29, 'c2:48:94:ab', 'A18WIJFW', 2, NULL, '2025-08-19 04:11:36', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-19 12:11:36', '2025-08-19 04:11:36', 'OK', NULL),
(279, 29, 'c2:48:94:ab', 'A18WIJFW', 3, NULL, '2025-08-19 04:11:51', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-19 12:11:51', '2025-08-19 04:11:51', 'OK', NULL),
(280, 29, 'c2:48:94:ab', 'A18WIJFW', 4, NULL, '2025-08-19 04:12:01', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -65, 'approved', '2025-08-19 12:12:01', '2025-08-19 04:12:01', 'OK', NULL),
(281, 29, 'c2:48:94:ab', 'A18WIJFW', 5, NULL, '2025-08-19 04:12:11', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-19 12:12:11', '2025-08-19 04:12:11', 'OK', NULL),
(282, 29, 'c2:48:94:ab', 'LJVLYGJB', 1, NULL, '2025-08-19 04:12:20', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-19 12:12:20', '2025-08-19 04:12:20', 'OK', NULL),
(283, 27, '4c:3f:b6:01', 'MLG7ZS6K', 2, NULL, '2025-08-19 04:15:05', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -76, 'approved', '2025-08-19 12:15:05', '2025-08-19 04:15:05', 'OK', NULL),
(284, 27, '4c:3f:b6:01', 'MLG7ZS6K', 3, NULL, '2025-08-19 04:15:20', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-19 12:15:20', '2025-08-19 04:15:20', 'OK', NULL),
(285, 27, '4c:3f:b6:01', 'MLG7ZS6K', 4, NULL, '2025-08-19 04:15:30', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 12:15:30', '2025-08-19 04:15:30', 'OK', NULL),
(286, 27, '4c:3f:b6:01', 'MLG7ZS6K', 5, NULL, '2025-08-19 04:15:39', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-19 12:15:39', '2025-08-19 04:15:39', 'OK', NULL),
(287, 27, '4c:3f:b6:01', 'TU8A4I60', 1, NULL, '2025-08-19 04:15:49', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -67, 'approved', '2025-08-19 12:15:49', '2025-08-19 04:15:49', 'OK', NULL),
(288, 27, '4c:3f:b6:01', 'TU8A4I60', 2, NULL, '2025-08-19 04:16:48', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-19 12:16:48', '2025-08-19 04:16:48', 'OK', NULL),
(289, 29, 'c2:48:94:ab', 'LJVLYGJB', 2, NULL, '2025-08-19 04:17:02', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-19 12:17:02', '2025-08-19 04:17:02', 'OK', NULL),
(290, 27, '4c:3f:b6:01', 'TU8A4I60', 3, NULL, '2025-08-19 04:17:15', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -66, 'approved', '2025-08-19 12:17:15', '2025-08-19 04:17:15', 'OK', NULL),
(291, 29, 'c2:48:94:ab', 'LJVLYGJB', 3, NULL, '2025-08-19 04:17:28', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 12:17:28', '2025-08-19 04:17:28', 'OK', NULL),
(292, 27, '4c:3f:b6:01', 'TU8A4I60', 4, NULL, '2025-08-19 04:17:42', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -64, 'approved', '2025-08-19 12:17:42', '2025-08-19 04:17:42', 'OK', NULL),
(293, 27, '4c:3f:b6:01', 'TU8A4I60', 5, NULL, '2025-08-19 04:17:56', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 12:17:56', '2025-08-19 04:17:56', 'OK', NULL),
(294, 29, 'c2:48:94:ab', 'LJVLYGJB', 4, NULL, '2025-08-19 04:18:19', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-19 12:18:19', '2025-08-19 04:18:19', 'OK', NULL),
(295, 29, 'c2:48:94:ab', 'LJVLYGJB', 5, NULL, '2025-08-19 04:18:33', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 12:18:33', '2025-08-19 04:18:33', 'OK', NULL),
(296, 28, '53:89:08:02', 'PUW7G5B6', 1, NULL, '2025-08-19 04:30:31', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-19 12:30:32', '2025-08-19 04:30:32', 'OK', NULL),
(297, 28, '53:89:08:02', 'PUW7G5B6', 2, NULL, '2025-08-19 04:31:08', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 12:31:08', '2025-08-19 04:31:08', 'OK', NULL),
(298, 28, '53:89:08:02', 'PUW7G5B6', 3, NULL, '2025-08-19 04:31:22', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -73, 'approved', '2025-08-19 12:31:22', '2025-08-19 04:31:22', 'OK', NULL),
(299, 28, '53:89:08:02', 'PUW7G5B6', 4, NULL, '2025-08-19 04:31:35', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-19 12:31:35', '2025-08-19 04:31:35', 'OK', NULL),
(300, 28, '53:89:08:02', 'PUW7G5B6', 5, NULL, '2025-08-19 04:31:48', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-19 12:31:48', '2025-08-19 04:31:48', 'OK', NULL),
(301, 32, '11:7b:b0:01', '9UAWJ9PP', 4, NULL, '2025-08-19 05:40:59', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -80, 'approved', '2025-08-19 13:40:59', '2025-08-19 05:40:59', 'OK', NULL),
(302, 32, '11:7b:b0:01', '9UAWJ9PP', 5, NULL, '2025-08-19 05:41:14', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-19 13:41:09', '2025-08-19 05:41:09', 'OK', NULL),
(303, 32, '11:7b:b0:01', 'F7A6UHDQ', 1, NULL, '2025-08-19 05:41:23', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -69, 'approved', '2025-08-19 13:41:23', '2025-08-19 05:41:23', 'OK', NULL),
(304, 32, '11:7b:b0:01', 'F7A6UHDQ', 2, NULL, '2025-08-19 05:41:33', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -75, 'approved', '2025-08-19 13:41:33', '2025-08-19 05:41:33', 'OK', NULL),
(305, 28, '53:89:08:02', 'ORR6PDB7', 1, NULL, '2025-08-19 05:41:43', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-19 13:41:43', '2025-08-19 05:41:43', 'OK', NULL),
(306, 28, '53:89:08:02', 'ORR6PDB7', 2, NULL, '2025-08-19 05:45:37', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -71, 'approved', '2025-08-19 13:45:37', '2025-08-19 05:45:37', 'OK', NULL),
(307, 28, '53:89:08:02', 'ORR6PDB7', 3, NULL, '2025-08-19 05:47:19', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 13:47:19', '2025-08-19 05:47:19', 'OK', NULL),
(308, 28, '53:89:08:02', 'ORR6PDB7', 4, NULL, '2025-08-19 05:51:04', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -63, 'approved', '2025-08-19 13:51:05', '2025-08-19 05:51:05', 'OK', NULL),
(309, 28, '53:89:08:02', 'ORR6PDB7', 5, NULL, '2025-08-19 05:51:43', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -66, 'approved', '2025-08-19 13:51:43', '2025-08-19 05:51:43', 'OK', NULL),
(310, 28, '53:89:08:02', 'DQOVZW0I', 1, NULL, '2025-08-19 05:53:01', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -74, 'approved', '2025-08-19 13:53:01', '2025-08-19 05:53:01', 'OK', NULL),
(311, 28, '53:89:08:02', 'DQOVZW0I', 2, NULL, '2025-08-19 05:53:35', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -72, 'approved', '2025-08-19 13:53:35', '2025-08-19 05:53:35', 'OK', NULL),
(312, 28, '53:89:08:02', 'DQOVZW0I', 3, NULL, '2025-08-19 05:54:02', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -70, 'approved', '2025-08-19 13:54:02', '2025-08-19 05:54:02', 'OK', NULL),
(313, 28, '53:89:08:02', 'DQOVZW0I', 4, NULL, '2025-08-19 05:54:45', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -68, 'approved', '2025-08-19 13:54:45', '2025-08-19 05:54:45', 'OK', NULL),
(314, 28, '53:89:08:02', 'DQOVZW0I', 5, NULL, '2025-08-19 05:58:05', 'ESP32-RFID-Scanner', 'PLDTHOMEFIBRc11f8', -63, 'approved', '2025-08-19 13:58:06', '2025-08-19 05:58:06', 'OK', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `services`
--

CREATE TABLE `services` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `duration_minutes` int(11) DEFAULT 60,
  `category` enum('basic','premium','addon') NOT NULL,
  `description` text DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `services`
--

INSERT INTO `services` (`id`, `name`, `price`, `duration_minutes`, `category`, `description`, `is_active`) VALUES
(1, 'Basic Bath', 300.00, 60, 'basic', 'Shampoo, rinse, and basic dry', 1),
(2, 'Nail Trimming', 150.00, 60, 'basic', 'Professional nail care', 1),
(3, 'Ear Cleaning', 200.00, 60, 'basic', 'Safe ear cleaning and inspection', 1),
(4, 'Full Grooming Package', 600.00, 60, 'premium', 'Bath, cut, style, nails, ears, and teeth', 1),
(5, 'Dental Care', 250.00, 60, 'premium', 'Teeth cleaning and oral health check', 1),
(6, 'De-shedding Treatment', 400.00, 60, 'premium', 'Reduces shedding up to 90%', 1),
(7, 'Nail Polish', 100.00, 60, 'addon', 'Pet-safe nail colors', 1),
(8, 'Perfume & Bow', 150.00, 60, 'addon', 'Finishing touches for a perfect look', 1);

-- --------------------------------------------------------

--
-- Table structure for table `status_updates`
--

CREATE TABLE `status_updates` (
  `id` int(11) NOT NULL,
  `booking_id` int(11) NOT NULL,
  `status` enum('checked-in','bathing','grooming','ready','completed') NOT NULL,
  `notes` text DEFAULT NULL,
  `updated_by` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `status_updates`
--

INSERT INTO `status_updates` (`id`, `booking_id`, `status`, `notes`, `updated_by`, `created_at`) VALUES
(27, 34, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 17:05:12'),
(28, 35, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 17:06:21'),
(29, 35, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 17:07:00'),
(30, 35, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 17:07:02'),
(31, 35, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 17:07:04'),
(32, 35, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 17:07:06'),
(33, 34, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 17:07:08'),
(34, 34, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 17:07:10'),
(35, 34, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 17:07:12'),
(36, 34, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 17:07:14'),
(37, 36, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 17:30:25'),
(38, 37, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 17:32:33'),
(39, 36, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 17:34:04'),
(40, 36, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 17:34:06'),
(41, 36, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 17:34:08'),
(42, 36, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 17:34:10'),
(43, 38, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 17:34:30'),
(44, 38, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 18:03:19'),
(45, 38, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 18:03:23'),
(46, 38, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 18:03:25'),
(47, 38, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 18:03:27'),
(48, 39, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 18:03:57'),
(49, 40, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 18:12:26'),
(50, 40, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 18:25:59'),
(51, 40, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 18:26:01'),
(52, 40, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 18:26:03'),
(53, 40, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 18:26:05'),
(54, 41, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 18:29:41'),
(55, 39, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 18:40:48'),
(56, 39, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 18:40:50'),
(57, 39, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 18:40:52'),
(58, 39, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 18:40:54'),
(59, 42, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 18:42:54'),
(60, 41, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 18:57:21'),
(61, 41, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 18:57:23'),
(62, 41, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 18:57:25'),
(63, 41, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 18:57:27'),
(64, 43, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 18:57:59'),
(65, 42, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 19:01:22'),
(66, 42, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 19:01:24'),
(67, 42, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 19:01:26'),
(68, 42, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 19:01:28'),
(69, 44, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 19:01:56'),
(70, 37, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-17 19:05:12'),
(71, 37, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-17 19:05:14'),
(72, 37, 'ready', 'Status updated via RFID tap', NULL, '2025-08-17 19:05:16'),
(73, 37, 'completed', 'Status updated via RFID tap', NULL, '2025-08-17 19:05:18'),
(74, 45, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 19:05:49'),
(75, 46, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-17 19:10:20'),
(76, 47, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 03:37:05'),
(77, 48, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 03:41:36'),
(78, 43, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 03:45:34'),
(79, 43, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 03:45:36'),
(80, 43, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 03:45:38'),
(81, 43, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 03:45:40'),
(82, 49, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 03:46:08'),
(83, 49, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 04:36:50'),
(84, 49, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 04:36:52'),
(85, 49, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 04:36:55'),
(86, 49, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 04:36:56'),
(87, 50, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 04:37:22'),
(88, 46, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 04:42:59'),
(89, 46, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 04:43:01'),
(90, 46, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 04:43:03'),
(91, 46, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 04:43:05'),
(92, 51, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 04:43:34'),
(93, 47, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 05:18:49'),
(94, 47, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 05:18:51'),
(95, 47, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 05:18:53'),
(96, 47, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 05:18:55'),
(97, 52, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 05:19:55'),
(98, 53, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 05:24:16'),
(99, 44, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 05:25:52'),
(100, 44, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 05:25:54'),
(101, 44, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 05:25:57'),
(102, 44, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 05:25:59'),
(103, 54, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 05:26:26'),
(104, 45, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 05:37:44'),
(105, 45, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 05:37:46'),
(106, 45, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 05:37:48'),
(107, 45, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 05:37:50'),
(108, 55, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 05:38:15'),
(109, 55, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 05:41:47'),
(110, 55, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 05:41:49'),
(111, 55, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 05:41:51'),
(112, 55, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 05:41:53'),
(113, 56, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 05:42:19'),
(114, 54, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 05:47:42'),
(115, 54, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 05:47:44'),
(116, 54, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 05:47:46'),
(117, 54, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 05:47:48'),
(118, 57, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 05:48:36'),
(119, 50, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 06:00:44'),
(120, 50, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 06:00:46'),
(121, 50, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 06:00:48'),
(122, 50, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 06:00:50'),
(123, 58, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 06:04:31'),
(124, 51, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 06:05:11'),
(125, 51, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 06:05:13'),
(126, 51, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 06:05:15'),
(127, 51, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 06:05:17'),
(128, 59, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 06:05:43'),
(129, 58, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 09:22:45'),
(130, 58, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 09:22:47'),
(131, 58, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 09:22:49'),
(132, 58, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 09:22:51'),
(133, 60, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 09:23:18'),
(134, 61, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 09:23:21'),
(135, 62, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 09:23:28'),
(136, 63, 'checked-in', 'Pet checked in successfully', NULL, '2025-08-18 09:23:28'),
(137, 59, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 09:32:56'),
(138, 59, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 09:32:58'),
(139, 59, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 09:33:00'),
(140, 59, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 09:33:02'),
(141, 64, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 09:42:25'),
(142, 48, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 10:23:03'),
(143, 48, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 10:23:05'),
(144, 48, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 10:23:07'),
(145, 48, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 10:23:09'),
(146, 65, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 10:23:37'),
(147, 53, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 10:26:02'),
(148, 53, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 10:26:04'),
(149, 53, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 10:26:06'),
(150, 53, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 10:26:08'),
(151, 66, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 10:26:35'),
(152, 56, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 10:28:48'),
(153, 56, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 10:28:50'),
(154, 56, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 10:28:52'),
(155, 56, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 10:28:54'),
(156, 67, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 10:29:20'),
(157, 62, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:21'),
(158, 62, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:23'),
(159, 62, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:25'),
(160, 62, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:27'),
(161, 63, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:29'),
(162, 63, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:31'),
(163, 63, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:33'),
(164, 63, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:35'),
(165, 61, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:37'),
(166, 61, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:39'),
(167, 61, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:41'),
(168, 61, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:43'),
(169, 60, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:45'),
(170, 60, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:47'),
(171, 60, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 10:36:49'),
(172, 68, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 10:36:54'),
(173, 68, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 10:50:19'),
(174, 68, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 10:50:21'),
(175, 68, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 10:50:23'),
(176, 68, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 10:50:25'),
(177, 69, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 10:50:40'),
(178, 52, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 12:19:49'),
(179, 52, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 12:19:51'),
(180, 52, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 12:19:53'),
(181, 52, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 12:19:55'),
(182, 70, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 12:20:24'),
(183, 69, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 12:50:03'),
(184, 69, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 12:50:05'),
(185, 69, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 12:50:07'),
(186, 69, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 12:50:09'),
(187, 71, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 12:50:37'),
(188, 71, 'bathing', 'Status updated via RFID tap', NULL, '2025-08-18 13:07:31'),
(189, 71, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 13:07:33'),
(190, 71, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 13:07:35'),
(191, 71, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 13:07:37'),
(192, 72, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 13:08:06'),
(193, 57, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-18 17:20:14'),
(194, 57, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 17:20:15'),
(195, 57, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 17:20:17'),
(196, 57, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 17:20:19'),
(197, 73, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 17:20:47'),
(198, 73, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-18 17:21:23'),
(199, 73, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-18 17:21:37'),
(200, 73, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-18 17:21:50'),
(201, 73, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 17:50:47'),
(202, 74, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 17:50:54'),
(203, 74, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-18 17:51:41'),
(204, 74, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-18 17:52:13'),
(205, 74, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-18 17:52:27'),
(206, 65, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-18 17:56:42'),
(207, 65, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-18 17:56:43'),
(208, 65, 'ready', 'Status updated via RFID tap', NULL, '2025-08-18 17:56:45'),
(209, 65, 'completed', 'Status updated via RFID tap', NULL, '2025-08-18 17:56:47'),
(210, 75, 'checked-in', 'Initial check-in completed', NULL, '2025-08-18 17:57:47'),
(211, 75, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-18 17:58:17'),
(212, 75, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-18 17:58:32'),
(213, 75, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-18 17:58:46'),
(214, 67, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 03:33:22'),
(215, 67, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-19 03:33:23'),
(216, 67, 'ready', 'Status updated via RFID tap', NULL, '2025-08-19 03:33:25'),
(217, 67, 'completed', 'Status updated via RFID tap', NULL, '2025-08-19 03:33:27'),
(218, 76, 'checked-in', 'Initial check-in completed', NULL, '2025-08-19 03:34:12'),
(219, 76, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 03:34:40'),
(220, 76, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-19 03:35:29'),
(221, 76, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-19 03:35:48'),
(222, 76, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 03:36:07'),
(223, 77, 'checked-in', 'Initial check-in completed', NULL, '2025-08-19 03:43:28'),
(224, 77, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 03:43:53'),
(225, 77, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-19 03:44:06'),
(226, 77, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-19 03:44:26'),
(227, 77, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 03:44:45'),
(228, 78, 'checked-in', 'Initial check-in completed', NULL, '2025-08-19 03:55:36'),
(229, 78, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 03:56:13'),
(230, 78, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-19 03:56:28'),
(231, 78, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-19 03:56:48'),
(232, 78, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 03:57:08'),
(233, 64, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 04:11:36'),
(234, 64, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-19 04:11:37'),
(235, 64, 'ready', 'Status updated via RFID tap', NULL, '2025-08-19 04:11:39'),
(236, 64, 'completed', 'Status updated via RFID tap', NULL, '2025-08-19 04:11:41'),
(237, 79, 'checked-in', 'Initial check-in completed', NULL, '2025-08-19 04:12:24'),
(238, 66, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 04:15:05'),
(239, 66, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-19 04:15:06'),
(240, 66, 'ready', 'Status updated via RFID tap', NULL, '2025-08-19 04:15:08'),
(241, 66, 'completed', 'Status updated via RFID tap', NULL, '2025-08-19 04:15:10'),
(242, 80, 'checked-in', 'Initial check-in completed', NULL, '2025-08-19 04:15:56'),
(243, 80, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 04:16:48'),
(244, 79, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 04:17:02'),
(245, 80, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-19 04:17:15'),
(246, 79, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-19 04:17:28'),
(247, 80, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-19 04:17:42'),
(248, 80, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 04:17:56'),
(249, 79, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-19 04:18:19'),
(250, 79, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 04:18:33'),
(251, 81, 'checked-in', 'Initial check-in completed', NULL, '2025-08-19 04:30:39'),
(252, 81, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 04:31:08'),
(253, 81, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-19 04:31:22'),
(254, 81, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-19 04:31:35'),
(255, 81, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 04:31:48'),
(256, 82, 'checked-in', 'Initial check-in completed', NULL, '2025-08-19 05:41:47'),
(257, 82, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 05:45:37'),
(258, 82, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-19 05:47:19'),
(259, 82, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-19 05:51:04'),
(260, 82, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 05:51:43'),
(261, 83, 'checked-in', 'Initial check-in completed', NULL, '2025-08-19 05:53:04'),
(262, 83, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-19 05:53:35'),
(263, 83, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-19 05:54:02'),
(264, 83, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-19 05:54:45'),
(265, 83, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 05:58:05');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `first_name` varchar(100) NOT NULL,
  `last_name` varchar(100) NOT NULL,
  `email` varchar(255) NOT NULL,
  `phone` varchar(20) NOT NULL,
  `emergency_contact_no` varchar(20) DEFAULT NULL,
  `emergency_contact_name` varchar(100) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `role` enum('customer','staff','admin') NOT NULL DEFAULT 'customer',
  `password_hash` varchar(255) NOT NULL,
  `email_verified` tinyint(1) DEFAULT 0,
  `email_verified_at` timestamp NULL DEFAULT NULL,
  `verification_code` varchar(6) DEFAULT NULL,
  `verification_token` varchar(64) DEFAULT NULL,
  `verification_code_expires` timestamp NOT NULL DEFAULT (current_timestamp() + interval 30 minute),
  `password_reset_token` varchar(64) DEFAULT NULL,
  `password_reset_code` varchar(6) DEFAULT NULL,
  `password_reset_code_expires` timestamp NULL DEFAULT NULL,
  `password_reset_expires` timestamp NULL DEFAULT NULL,
  `marketing_emails` tinyint(1) DEFAULT 0,
  `is_active` tinyint(1) DEFAULT 1,
  `last_login` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`id`, `first_name`, `last_name`, `email`, `phone`, `emergency_contact_no`, `emergency_contact_name`, `address`, `role`, `password_hash`, `email_verified`, `email_verified_at`, `verification_code`, `verification_token`, `verification_code_expires`, `password_reset_token`, `password_reset_code`, `password_reset_code_expires`, `password_reset_expires`, `marketing_emails`, `is_active`, `last_login`, `created_at`, `updated_at`) VALUES
(1, 'Admin', 'User', 'admin@8pawspetboutique.com', '0912-345-6789', NULL, NULL, NULL, 'customer', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 1, '2025-08-14 08:47:58', NULL, NULL, '2025-08-14 09:17:58', NULL, NULL, NULL, NULL, 0, 1, NULL, '2025-08-14 08:47:58', '2025-08-14 08:47:58'),
(10, 'Test', 'Test', 'ivyrivera50@gmail.com', '0967-663-6689', NULL, NULL, NULL, 'customer', '$2y$10$41Sly1tQvQqsCipqmNiis.59lukjTqJewI9a6cVQ2pKJOXBilv97i', 1, '2025-08-14 09:21:17', NULL, NULL, '2025-08-14 09:50:58', NULL, NULL, NULL, NULL, 1, 1, NULL, '2025-08-14 09:20:58', '2025-08-14 09:21:17'),
(12, 'Bryant Iverson', 'Melliza', 'bryantiversonmelliza03@gmail.com', '0939-817-0375', '0939-817-0375', 'Bryant Iverson Cervantes Melliza', '1110 MBA Compound Barangay Bagumbong Caloocan City', 'customer', '$2y$10$n8N1Xk8L6fKtsqLNCP4ReOVL/71ftB7RLHz39it5dq.hQ6NsJypyW', 1, '2025-08-16 14:14:53', NULL, NULL, '2025-08-16 14:44:06', NULL, NULL, NULL, '2025-08-18 09:16:26', 0, 1, '2025-08-19 16:58:42', '2025-08-16 14:14:06', '2025-08-19 16:58:42'),
(13, 'Bryant Iverson', 'Melliza', 'brybry.melliza@gmail.com', '0939-817-0378', '0939-817-0378', 'Bryant Iverson Cervantes Melliza', '1110 MBA Compound Barangay Bagumbong Caloocan City', 'staff', '$2y$10$Z2ZrpD0d4zm/5bEnoPSs9utO48ExJ7UO1mhgWDzGj3Vz9kN/uBxIi', 1, '2025-08-16 14:47:48', NULL, NULL, '2025-08-16 15:17:21', NULL, NULL, NULL, NULL, 0, 1, '2025-08-16 15:38:49', '2025-08-16 14:47:21', '2025-08-19 15:50:27'),
(15, 'Bryant Iverson', 'Melliza', 'bryantiversonmelliza@gmail.com', '0939-817-0373', '0939-817-0375', 'Bryant Iverson Cervantes Melliza', '1110 MBA Compound Barangay Bagumbong Caloocan City', 'customer', '$2y$10$Hgc4SMpEPqn9rWp1Oj.cBODknt1lwPjrDYF/Ca5Hr24EWseh7EVym', 0, NULL, '947147', '6ed55d53c27b44f98824e941cd5979660d6bbb7e5258671eb397ebf6efee3d05', '2025-08-18 14:48:28', NULL, NULL, NULL, NULL, 0, 1, NULL, '2025-08-18 14:18:28', '2025-08-18 14:18:28');

-- --------------------------------------------------------

--
-- Stand-in structure for view `user_dashboard_view`
-- (See below for the actual view)
--
CREATE TABLE `user_dashboard_view` (
);

-- --------------------------------------------------------

--
-- Structure for view `booking_rfid_view`
--
DROP TABLE IF EXISTS `booking_rfid_view`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `booking_rfid_view`  AS SELECT `b`.`id` AS `booking_id`, `b`.`custom_rfid` AS `custom_rfid`, `b`.`status` AS `status`, `b`.`total_amount` AS `total_amount`, `b`.`check_in_time` AS `check_in_time`, `b`.`estimated_completion` AS `estimated_completion`, `b`.`actual_completion` AS `actual_completion`, `p`.`name` AS `pet_name`, `p`.`type` AS `pet_type`, `p`.`breed` AS `pet_breed`, `c`.`name` AS `owner_name`, `c`.`phone` AS `owner_phone`, `c`.`email` AS `owner_email`, `rc`.`tap_count` AS `tap_count`, `rc`.`max_taps` AS `max_taps`, `rc`.`card_uid` AS `card_uid`, CASE WHEN `b`.`status` = 'checked-in' THEN 'Waiting for first service' WHEN `b`.`status` = 'bathing' THEN 'Currently bathing' WHEN `b`.`status` = 'grooming' THEN 'Currently grooming' WHEN `b`.`status` = 'ready' THEN 'Ready for pickup' WHEN `b`.`status` = 'completed' THEN 'Completed' ELSE 'Unknown status' END AS `status_description` FROM (((`bookings` `b` left join `pets` `p` on(`b`.`pet_id` = `p`.`id`)) left join `customers` `c` on(`p`.`customer_id` = `c`.`id`)) left join `rfid_cards` `rc` on(`b`.`custom_rfid` = `rc`.`custom_uid`)) WHERE `b`.`custom_rfid` is not null ;

-- --------------------------------------------------------

--
-- Structure for view `user_dashboard_view`
--
DROP TABLE IF EXISTS `user_dashboard_view`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `user_dashboard_view`  AS SELECT `u`.`id` AS `user_id`, `u`.`first_name` AS `first_name`, `u`.`last_name` AS `last_name`, `u`.`email` AS `email`, `u`.`phone` AS `phone`, `u`.`last_login` AS `last_login`, count(distinct `up`.`pet_id`) AS `total_pets`, count(distinct case when `b`.`status` not in ('completed','cancelled') then `b`.`id` end) AS `active_bookings`, count(distinct case when `b`.`status` = 'completed' then `b`.`id` end) AS `completed_bookings`, max(`b`.`created_at`) AS `last_booking_date`, sum(case when `b`.`status` = 'completed' then `b`.`total_amount` else 0 end) AS `total_spent` FROM ((`users` `u` left join `user_pets` `up` on(`u`.`id` = `up`.`user_id`)) left join `bookings` `b` on(`u`.`id` = `b`.`user_id`)) GROUP BY `u`.`id`, `u`.`first_name`, `u`.`last_name`, `u`.`email`, `u`.`phone`, `u`.`last_login` ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `appointments`
--
ALTER TABLE `appointments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `pet_id` (`pet_id`),
  ADD KEY `idx_appointment_date` (`appointment_date`),
  ADD KEY `idx_user_date` (`user_id`,`appointment_date`),
  ADD KEY `idx_status` (`status`);

--
-- Indexes for table `appointment_services`
--
ALTER TABLE `appointment_services`
  ADD PRIMARY KEY (`id`),
  ADD KEY `service_id` (`service_id`),
  ADD KEY `idx_appointment` (`appointment_id`);

--
-- Indexes for table `app_config`
--
ALTER TABLE `app_config`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `config_key` (`config_key`),
  ADD KEY `idx_config_key` (`config_key`);

--
-- Indexes for table `bookings`
--
ALTER TABLE `bookings`
  ADD PRIMARY KEY (`id`),
  ADD KEY `pet_id` (`pet_id`),
  ADD KEY `rfid_tag_id` (`rfid_tag_id`),
  ADD KEY `fk_bookings_users` (`user_id`),
  ADD KEY `idx_custom_rfid` (`custom_rfid`),
  ADD KEY `idx_status_created` (`status`,`created_at`),
  ADD KEY `rfid_card_id` (`rfid_card_id`);

--
-- Indexes for table `booking_services`
--
ALTER TABLE `booking_services`
  ADD PRIMARY KEY (`id`),
  ADD KEY `booking_id` (`booking_id`),
  ADD KEY `service_id` (`service_id`);

--
-- Indexes for table `customers`
--
ALTER TABLE `customers`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_customers_users` (`user_id`);

--
-- Indexes for table `pets`
--
ALTER TABLE `pets`
  ADD PRIMARY KEY (`id`),
  ADD KEY `customer_id` (`customer_id`);

--
-- Indexes for table `rfid_cards`
--
ALTER TABLE `rfid_cards`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `card_uid` (`card_uid`),
  ADD KEY `idx_card_uid` (`card_uid`),
  ADD KEY `idx_custom_uid` (`custom_uid`),
  ADD KEY `idx_created_at` (`created_at`),
  ADD KEY `idx_firebase_doc` (`firebase_doc_id`),
  ADD KEY `idx_status` (`status`);

--
-- Indexes for table `rfid_tags`
--
ALTER TABLE `rfid_tags`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `tag_id` (`tag_id`),
  ADD KEY `pet_id` (`pet_id`);

--
-- Indexes for table `rfid_tap_history`
--
ALTER TABLE `rfid_tap_history`
  ADD PRIMARY KEY (`id`),
  ADD KEY `rfid_card_id` (`rfid_card_id`),
  ADD KEY `idx_card_uid` (`card_uid`),
  ADD KEY `idx_custom_uid` (`custom_uid`),
  ADD KEY `idx_tapped_at` (`tapped_at`),
  ADD KEY `idx_firebase_doc` (`firebase_doc_id`),
  ADD KEY `idx_validation_status` (`validation_status`);

--
-- Indexes for table `services`
--
ALTER TABLE `services`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `status_updates`
--
ALTER TABLE `status_updates`
  ADD PRIMARY KEY (`id`),
  ADD KEY `booking_id` (`booking_id`),
  ADD KEY `idx_booking_created` (`booking_id`,`created_at`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`),
  ADD UNIQUE KEY `phone` (`phone`),
  ADD KEY `idx_email` (`email`),
  ADD KEY `idx_phone` (`phone`),
  ADD KEY `idx_verification_token` (`verification_token`),
  ADD KEY `idx_password_reset_token` (`password_reset_token`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `appointments`
--
ALTER TABLE `appointments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `appointment_services`
--
ALTER TABLE `appointment_services`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `app_config`
--
ALTER TABLE `app_config`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `bookings`
--
ALTER TABLE `bookings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=84;

--
-- AUTO_INCREMENT for table `booking_services`
--
ALTER TABLE `booking_services`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=250;

--
-- AUTO_INCREMENT for table `customers`
--
ALTER TABLE `customers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=24;

--
-- AUTO_INCREMENT for table `pets`
--
ALTER TABLE `pets`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=106;

--
-- AUTO_INCREMENT for table `rfid_cards`
--
ALTER TABLE `rfid_cards`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=33;

--
-- AUTO_INCREMENT for table `rfid_tags`
--
ALTER TABLE `rfid_tags`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `rfid_tap_history`
--
ALTER TABLE `rfid_tap_history`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=315;

--
-- AUTO_INCREMENT for table `services`
--
ALTER TABLE `services`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `status_updates`
--
ALTER TABLE `status_updates`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=266;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `appointments`
--
ALTER TABLE `appointments`
  ADD CONSTRAINT `appointments_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `appointments_ibfk_2` FOREIGN KEY (`pet_id`) REFERENCES `pets` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `appointment_services`
--
ALTER TABLE `appointment_services`
  ADD CONSTRAINT `appointment_services_ibfk_1` FOREIGN KEY (`appointment_id`) REFERENCES `appointments` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `appointment_services_ibfk_2` FOREIGN KEY (`service_id`) REFERENCES `services` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `bookings`
--
ALTER TABLE `bookings`
  ADD CONSTRAINT `bookings_ibfk_1` FOREIGN KEY (`pet_id`) REFERENCES `pets` (`id`),
  ADD CONSTRAINT `bookings_ibfk_2` FOREIGN KEY (`rfid_card_id`) REFERENCES `rfid_cards` (`id`),
  ADD CONSTRAINT `fk_bookings_rfid_cards` FOREIGN KEY (`rfid_tag_id`) REFERENCES `rfid_cards` (`id`),
  ADD CONSTRAINT `fk_bookings_users` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `booking_services`
--
ALTER TABLE `booking_services`
  ADD CONSTRAINT `booking_services_ibfk_1` FOREIGN KEY (`booking_id`) REFERENCES `bookings` (`id`),
  ADD CONSTRAINT `booking_services_ibfk_2` FOREIGN KEY (`service_id`) REFERENCES `services` (`id`);

--
-- Constraints for table `customers`
--
ALTER TABLE `customers`
  ADD CONSTRAINT `fk_customers_users` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `pets`
--
ALTER TABLE `pets`
  ADD CONSTRAINT `pets_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`);

--
-- Constraints for table `rfid_tags`
--
ALTER TABLE `rfid_tags`
  ADD CONSTRAINT `rfid_tags_ibfk_1` FOREIGN KEY (`pet_id`) REFERENCES `pets` (`id`);

--
-- Constraints for table `rfid_tap_history`
--
ALTER TABLE `rfid_tap_history`
  ADD CONSTRAINT `rfid_tap_history_ibfk_1` FOREIGN KEY (`rfid_card_id`) REFERENCES `rfid_cards` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `status_updates`
--
ALTER TABLE `status_updates`
  ADD CONSTRAINT `status_updates_ibfk_1` FOREIGN KEY (`booking_id`) REFERENCES `bookings` (`id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
