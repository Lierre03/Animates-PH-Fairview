-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Aug 24, 2025 at 02:25 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

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
(83, 105, 28, NULL, 'DQOVZW0I', 950.00, 'completed', '2025-08-19 05:53:04', '2025-08-19 07:53:04', '2025-08-19 05:58:05', NULL, NULL, '2025-08-19 05:53:04', '2025-08-19 05:58:05', NULL, 'walk_in', 1),
(87, 109, 27, NULL, '5XHLLBXO', 250.00, 'completed', '2025-08-22 19:13:54', '2025-08-22 21:13:54', NULL, NULL, NULL, '2025-08-22 19:13:54', '2025-08-24 09:25:46', NULL, 'walk_in', 0),
(88, 110, 29, NULL, 'OPE4RF3R', 150.00, 'completed', '2025-08-22 19:20:50', '2025-08-22 21:20:50', '2025-08-22 19:25:04', NULL, NULL, '2025-08-22 19:20:50', '2025-08-22 19:25:04', NULL, 'walk_in', 0),
(89, 111, 28, NULL, 'WDT9SNDG', 600.00, 'completed', '2025-08-23 19:03:14', '2025-08-23 21:03:14', NULL, NULL, NULL, '2025-08-23 19:03:14', '2025-08-23 19:30:55', NULL, 'walk_in', 0),
(90, 112, 28, NULL, '4VCKU0HP', 600.00, 'completed', '2025-08-23 19:31:45', '2025-08-23 21:31:45', '2025-08-24 11:21:31', NULL, NULL, '2025-08-23 19:31:45', '2025-08-24 11:21:32', NULL, 'walk_in', 0),
(91, 113, 27, NULL, 'AVM7U0Z4', 600.00, 'completed', '2025-08-24 09:26:24', '2025-08-24 11:26:24', NULL, NULL, NULL, '2025-08-24 09:26:24', '2025-08-24 09:33:15', NULL, 'walk_in', 1),
(92, 114, 27, NULL, 'EG0WX4DO', 850.00, 'completed', '2025-08-24 11:11:40', '2025-08-24 13:11:40', NULL, NULL, NULL, '2025-08-24 11:11:40', '2025-08-24 11:32:10', NULL, 'walk_in', 1),
(93, 115, 28, NULL, 'DPHJS82Z', 150.00, 'completed', '2025-08-24 11:22:41', '2025-08-24 13:22:41', NULL, NULL, NULL, '2025-08-24 11:22:41', '2025-08-24 11:29:44', NULL, 'walk_in', 1),
(94, 116, 27, NULL, '55MS62AZ', 250.00, 'completed', '2025-08-24 11:32:56', '2025-08-24 13:32:56', NULL, NULL, NULL, '2025-08-24 11:32:56', '2025-08-24 11:38:13', NULL, 'walk_in', 1),
(95, 117, 27, NULL, '18MG8OEF', 120.00, 'completed', '2025-08-24 11:39:25', '2025-08-24 13:39:25', NULL, NULL, NULL, '2025-08-24 11:39:25', '2025-08-24 12:04:45', NULL, 'walk_in', 1),
(96, 118, 28, NULL, 'ZKAISC8V', 750.00, 'completed', '2025-08-24 11:48:00', '2025-08-24 13:48:00', NULL, NULL, NULL, '2025-08-24 11:48:00', '2025-08-24 12:03:11', NULL, 'walk_in', 1),
(97, 119, 27, NULL, '3ECMH79O', 250.00, 'checked-in', '2025-08-24 12:14:29', '2025-08-24 14:14:29', NULL, NULL, NULL, '2025-08-24 12:14:29', '2025-08-24 12:14:35', NULL, 'walk_in', 1);

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
  `price` decimal(10,2) NOT NULL,
  `pet_size` enum('small','medium','large','extra_large') DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `booking_services`
--

INSERT INTO `booking_services` (`id`, `booking_id`, `service_id`, `price`, `pet_size`) VALUES
(51, 34, 3, 200.00, 'large'),
(52, 34, 5, 250.00, 'large'),
(53, 34, 8, 150.00, 'large'),
(54, 35, 6, 400.00, 'medium'),
(55, 36, 2, 150.00, 'medium'),
(56, 36, 3, 200.00, 'medium'),
(57, 37, 4, 600.00, 'small'),
(58, 38, 5, 250.00, 'medium'),
(59, 38, 6, 400.00, 'medium'),
(60, 39, 4, 600.00, 'medium'),
(61, 39, 7, 100.00, 'medium'),
(62, 40, 1, 300.00, 'medium'),
(63, 40, 4, 600.00, 'medium'),
(64, 40, 8, 150.00, 'medium'),
(65, 41, 3, 200.00, 'small'),
(66, 41, 6, 400.00, 'small'),
(67, 41, 8, 150.00, 'small'),
(68, 42, 3, 200.00, 'medium'),
(69, 42, 6, 400.00, 'medium'),
(70, 42, 8, 150.00, 'medium'),
(71, 43, 1, 300.00, 'medium'),
(72, 43, 4, 600.00, 'medium'),
(73, 43, 8, 150.00, 'medium'),
(74, 44, 1, 300.00, 'small'),
(75, 44, 4, 600.00, 'small'),
(76, 44, 7, 100.00, 'small'),
(77, 45, 3, 200.00, 'small'),
(78, 45, 4, 600.00, 'small'),
(79, 45, 6, 400.00, 'small'),
(80, 45, 7, 100.00, 'small'),
(81, 46, 2, 150.00, 'small'),
(82, 46, 4, 600.00, 'small'),
(83, 46, 7, 100.00, 'small'),
(84, 47, 1, 300.00, 'small'),
(85, 47, 2, 150.00, 'small'),
(86, 47, 4, 600.00, 'small'),
(87, 47, 5, 250.00, 'small'),
(88, 47, 6, 400.00, 'small'),
(89, 47, 7, 100.00, 'small'),
(90, 48, 1, 300.00, 'small'),
(91, 48, 2, 150.00, 'small'),
(92, 48, 3, 200.00, 'small'),
(93, 48, 4, 600.00, 'small'),
(94, 48, 5, 250.00, 'small'),
(95, 48, 6, 400.00, 'small'),
(96, 48, 7, 100.00, 'small'),
(97, 48, 8, 150.00, 'small'),
(98, 49, 1, 300.00, 'medium'),
(99, 49, 2, 150.00, 'medium'),
(100, 49, 3, 200.00, 'medium'),
(101, 49, 4, 600.00, 'medium'),
(102, 49, 5, 250.00, 'medium'),
(103, 49, 6, 400.00, 'medium'),
(104, 49, 7, 100.00, 'medium'),
(105, 49, 8, 150.00, 'medium'),
(106, 50, 2, 150.00, 'small'),
(107, 50, 4, 600.00, 'small'),
(108, 50, 7, 100.00, 'small'),
(109, 51, 1, 300.00, 'small'),
(110, 51, 2, 150.00, 'small'),
(111, 51, 3, 200.00, 'small'),
(112, 51, 4, 600.00, 'small'),
(113, 51, 5, 250.00, 'small'),
(114, 51, 6, 400.00, 'small'),
(115, 51, 7, 100.00, 'small'),
(116, 51, 8, 150.00, 'small'),
(117, 52, 1, 300.00, 'medium'),
(118, 52, 2, 150.00, 'medium'),
(119, 52, 4, 600.00, 'medium'),
(120, 52, 5, 250.00, 'medium'),
(121, 52, 7, 100.00, 'medium'),
(122, 53, 1, 300.00, 'medium'),
(123, 53, 2, 150.00, 'medium'),
(124, 53, 3, 200.00, 'medium'),
(125, 53, 4, 600.00, 'medium'),
(126, 53, 5, 250.00, 'medium'),
(127, 53, 6, 400.00, 'medium'),
(128, 53, 7, 100.00, 'medium'),
(129, 53, 8, 150.00, 'medium'),
(130, 54, 1, 300.00, 'large'),
(131, 54, 2, 150.00, 'large'),
(132, 54, 3, 200.00, 'large'),
(133, 54, 4, 600.00, 'large'),
(134, 54, 5, 250.00, 'large'),
(135, 54, 6, 400.00, 'large'),
(136, 54, 7, 100.00, 'large'),
(137, 54, 8, 150.00, 'large'),
(138, 55, 1, 300.00, 'large'),
(139, 55, 2, 150.00, 'large'),
(140, 55, 4, 600.00, 'large'),
(141, 55, 8, 150.00, 'large'),
(142, 56, 2, 150.00, 'medium'),
(143, 56, 4, 600.00, 'medium'),
(144, 56, 7, 100.00, 'medium'),
(145, 57, 1, 300.00, 'medium'),
(146, 57, 2, 150.00, 'medium'),
(147, 57, 3, 200.00, 'medium'),
(148, 57, 5, 250.00, 'medium'),
(149, 57, 6, 400.00, 'medium'),
(150, 57, 7, 100.00, 'medium'),
(151, 58, 4, 600.00, 'medium'),
(152, 58, 5, 250.00, 'medium'),
(153, 58, 6, 400.00, 'medium'),
(154, 58, 7, 100.00, 'medium'),
(155, 58, 8, 150.00, 'medium'),
(156, 59, 1, 300.00, 'large'),
(157, 59, 2, 150.00, 'large'),
(158, 59, 3, 200.00, 'large'),
(159, 59, 4, 600.00, 'large'),
(160, 59, 5, 250.00, 'large'),
(161, 59, 6, 400.00, 'large'),
(162, 59, 7, 100.00, 'large'),
(163, 59, 8, 150.00, 'large'),
(164, 60, 2, 150.00, 'small'),
(165, 60, 4, 600.00, 'small'),
(166, 60, 6, 400.00, 'small'),
(167, 60, 8, 150.00, 'small'),
(168, 61, 2, 150.00, 'small'),
(169, 61, 4, 600.00, 'small'),
(170, 61, 6, 400.00, 'small'),
(171, 61, 8, 150.00, 'small'),
(172, 62, 2, 150.00, 'small'),
(173, 62, 4, 600.00, 'small'),
(174, 62, 6, 400.00, 'small'),
(175, 62, 8, 150.00, 'small'),
(176, 63, 2, 150.00, 'small'),
(177, 63, 4, 600.00, 'small'),
(178, 63, 6, 400.00, 'small'),
(179, 63, 8, 150.00, 'small'),
(180, 64, 3, 200.00, 'small'),
(181, 64, 4, 600.00, 'small'),
(182, 64, 7, 100.00, 'small'),
(183, 64, 8, 150.00, 'small'),
(184, 65, 2, 150.00, 'medium'),
(185, 65, 5, 250.00, 'medium'),
(186, 65, 7, 100.00, 'medium'),
(187, 66, 1, 300.00, 'medium'),
(188, 66, 2, 150.00, 'medium'),
(189, 66, 3, 200.00, 'medium'),
(190, 66, 4, 600.00, 'medium'),
(191, 66, 7, 100.00, 'medium'),
(192, 67, 2, 150.00, 'medium'),
(193, 67, 3, 200.00, 'medium'),
(194, 67, 6, 400.00, 'medium'),
(195, 67, 7, 100.00, 'medium'),
(196, 68, 1, 300.00, 'medium'),
(197, 68, 2, 150.00, 'medium'),
(198, 68, 4, 600.00, 'medium'),
(199, 68, 6, 400.00, 'medium'),
(200, 68, 7, 100.00, 'medium'),
(201, 69, 2, 150.00, 'medium'),
(202, 69, 4, 600.00, 'medium'),
(203, 69, 8, 150.00, 'medium'),
(204, 70, 1, 300.00, 'medium'),
(205, 70, 2, 150.00, 'medium'),
(206, 70, 5, 250.00, 'medium'),
(207, 70, 7, 100.00, 'medium'),
(208, 71, 3, 200.00, 'medium'),
(209, 71, 5, 250.00, 'medium'),
(210, 72, 3, 200.00, 'medium'),
(211, 72, 4, 600.00, 'medium'),
(212, 72, 5, 250.00, 'medium'),
(213, 72, 7, 100.00, 'medium'),
(214, 73, 1, 300.00, 'small'),
(215, 73, 2, 150.00, 'small'),
(216, 73, 3, 200.00, 'small'),
(217, 73, 5, 250.00, 'small'),
(218, 73, 8, 150.00, 'small'),
(219, 74, 3, 200.00, 'large'),
(220, 74, 5, 250.00, 'large'),
(221, 74, 7, 100.00, 'large'),
(222, 75, 3, 200.00, 'small'),
(223, 76, 1, 300.00, 'medium'),
(224, 76, 2, 150.00, 'medium'),
(225, 76, 4, 600.00, 'medium'),
(226, 76, 8, 150.00, 'medium'),
(227, 77, 1, 300.00, 'medium'),
(228, 77, 2, 150.00, 'medium'),
(229, 77, 3, 200.00, 'medium'),
(230, 77, 5, 250.00, 'medium'),
(231, 77, 6, 400.00, 'medium'),
(232, 77, 7, 100.00, 'medium'),
(233, 78, 1, 300.00, 'medium'),
(234, 78, 5, 250.00, 'medium'),
(235, 78, 8, 150.00, 'medium'),
(236, 79, 1, 300.00, 'small'),
(237, 79, 2, 150.00, 'small'),
(238, 79, 3, 200.00, 'small'),
(239, 79, 5, 250.00, 'small'),
(240, 79, 8, 150.00, 'small'),
(241, 80, 4, 600.00, 'medium'),
(242, 80, 5, 250.00, 'medium'),
(243, 81, 3, 200.00, 'medium'),
(244, 81, 5, 250.00, 'medium'),
(245, 82, 4, 600.00, 'small'),
(246, 82, 8, 150.00, 'small'),
(247, 83, 3, 200.00, 'large'),
(248, 83, 4, 600.00, 'large'),
(249, 83, 8, 150.00, 'large'),
(253, 87, 5, 250.00, 'large'),
(254, 88, 2, 150.00, NULL),
(255, 89, 4, 600.00, 'large'),
(256, 90, 4, 600.00, 'medium'),
(257, 91, 4, 600.00, 'medium'),
(258, 92, 1, 250.00, NULL),
(259, 92, 4, 500.00, NULL),
(260, 92, 7, 100.00, NULL),
(261, 93, 2, 150.00, NULL),
(262, 94, 1, 250.00, NULL),
(263, 95, 2, 120.00, NULL),
(264, 96, 4, 750.00, NULL),
(265, 97, 1, 250.00, NULL);

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
(1, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-22 19:03:18', '2025-08-22 19:03:18', NULL, 'walk_in'),
(17, 'Bryant Iverson C. Melliza', '0943-135-9316', 'athegreat124@gmail.com', NULL, NULL, '2025-08-17 17:05:12', '2025-08-19 04:15:56', NULL, 'walk_in'),
(18, 'Bryant Iverson C. Melliza', '0939-817-0375', 'bryantiversonmelliza03@gmail.com', NULL, NULL, '2025-08-18 04:43:34', '2025-08-19 03:34:12', NULL, 'walk_in'),
(19, 'Ivy Rivera', '0943-131-2312', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-19 03:43:28', '2025-08-19 03:43:28', NULL, 'walk_in'),
(20, 'Bryant Iverson C. Melliza', '0931-425-6346', 'bryantiversonmelliza03@gmail.com', NULL, NULL, '2025-08-19 03:55:36', '2025-08-19 04:12:24', NULL, 'walk_in'),
(21, 'Iverson melliza', '0939-817-0375', 'bryantiversonmelliza@gmail.com', NULL, NULL, '2025-08-19 04:30:39', '2025-08-19 04:30:39', NULL, 'walk_in'),
(22, 'Bryant Iverson C. Melliza', '0939-817-0375', 'bryantiversonmelliza03@gmail.com', NULL, NULL, '2025-08-19 05:41:47', '2025-08-19 05:41:47', NULL, 'walk_in'),
(23, 'Bryant Iverson C. Melliza', '0943-135-9316', 'bryantiversonmelliza03@gmail.com', NULL, NULL, '2025-08-19 05:53:04', '2025-08-19 05:53:04', NULL, 'walk_in'),
(27, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-22 19:13:54', '2025-08-22 19:13:54', NULL, 'walk_in'),
(28, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-22 19:20:50', '2025-08-22 19:20:50', NULL, 'walk_in'),
(29, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-23 19:03:14', '2025-08-23 19:03:14', NULL, 'walk_in'),
(30, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-23 19:31:45', '2025-08-23 19:31:45', NULL, 'walk_in'),
(31, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-24 09:26:24', '2025-08-24 09:26:24', NULL, 'walk_in'),
(32, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-24 11:11:40', '2025-08-24 11:11:40', NULL, 'walk_in'),
(33, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-24 11:22:41', '2025-08-24 11:22:41', NULL, 'walk_in'),
(34, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-24 11:32:55', '2025-08-24 11:32:55', NULL, 'walk_in'),
(35, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-24 11:39:25', '2025-08-24 11:39:25', NULL, 'walk_in'),
(36, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-24 11:48:00', '2025-08-24 11:48:00', NULL, 'walk_in'),
(37, 'Ivy', '0912-344-3434', 'ivyrivera50@gmail.com', NULL, NULL, '2025-08-24 12:14:29', '2025-08-24 12:14:29', NULL, 'walk_in');

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
(1, 0, 'Buddy', 'dog', 'dog', 'buhund', 'young', 'large', '', '2025-08-22 19:03:18', '2025-08-22 19:03:18'),
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
(105, 23, 'tanggol', 'dog', 'dog', 'african', 'young', 'large', '', '2025-08-19 05:53:04', '2025-08-19 05:53:04'),
(109, 27, 'Buddy', 'dog', 'dog', 'brabancon', 'young', 'large', '', '2025-08-22 19:13:54', '2025-08-22 19:13:54'),
(110, 28, 'Buddy', 'dog', 'dog', 'bulldog', 'young', NULL, '', '2025-08-22 19:20:50', '2025-08-22 19:20:50'),
(111, 29, 'Buddy', 'cat', 'cat', 'Chantilly-Tiffany', 'young', 'large', '', '2025-08-23 19:03:14', '2025-08-23 19:03:14'),
(112, 30, 'Buddy', 'dog', 'dog', 'african', 'adult', 'medium', '', '2025-08-23 19:31:45', '2025-08-23 19:31:45'),
(113, 31, 'Buddy', 'cat', 'cat', 'Balinese', 'young', 'medium', '', '2025-08-24 09:26:24', '2025-08-24 09:26:24'),
(114, 32, 'Buddy', 'cat', 'cat', 'Abyssinian', 'young', 'small', '', '2025-08-24 11:11:40', '2025-08-24 11:11:40'),
(115, 33, 'Buddy', 'dog', 'dog', 'brabancon', 'young', 'medium', '', '2025-08-24 11:22:41', '2025-08-24 11:22:41'),
(116, 34, 'Buddy', 'dog', 'dog', 'bluetick', 'young', NULL, '', '2025-08-24 11:32:56', '2025-08-24 11:32:56'),
(117, 35, 'Buddy', 'cat', 'cat', 'Bengal', 'young', NULL, '', '2025-08-24 11:39:25', '2025-08-24 11:39:25'),
(118, 36, 'Buddy', 'cat', 'cat', 'Bombay', 'young', NULL, '', '2025-08-24 11:48:00', '2025-08-24 11:48:00'),
(119, 37, 'Buddy', 'cat', 'cat', 'Abyssinian', 'young', NULL, '', '2025-08-24 12:14:29', '2025-08-24 12:14:29');

-- --------------------------------------------------------

--
-- Table structure for table `pet_sizes`
--

CREATE TABLE `pet_sizes` (
  `id` int(11) NOT NULL,
  `size_code` enum('small','medium','large','extra_large') NOT NULL,
  `display_name` varchar(50) NOT NULL,
  `weight_range` varchar(50) DEFAULT NULL,
  `description` text DEFAULT NULL,
  `sort_order` int(11) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `pet_sizes`
--

INSERT INTO `pet_sizes` (`id`, `size_code`, `display_name`, `weight_range`, `description`, `sort_order`) VALUES
(1, 'small', 'Small', '0-15 lbs', 'Small pets (e.g., Chihuahua, Cat)', 1),
(2, 'medium', 'Medium', '16-40 lbs', 'Medium pets (e.g., Beagle, Cocker Spaniel)', 2),
(3, 'large', 'Large', '41-70 lbs', 'Large pets (e.g., Golden Retriever, German Shepherd)', 3),
(4, 'extra_large', 'Extra Large', '71+ lbs', 'Extra large pets (e.g., Great Dane, St. Bernard)', 4);

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
(27, '4c:3f:b6:01', '3ECMH79O', NULL, 1, 5, '2025-08-17 17:07:19', '2025-08-24 12:12:45', 1, '2025-08-24 12:12:45', 3000, 'ESP32-RFID-Scanner', 'active'),
(28, '53:89:08:02', 'ZKAISC8V', NULL, 4, 5, '2025-08-17 17:31:20', '2025-08-24 12:09:39', 1, '2025-08-24 12:09:39', 3000, 'ESP32-RFID-Scanner', 'active'),
(29, 'c2:48:94:ab', 'EZSRFAII', NULL, 2, 5, '2025-08-17 17:33:29', '2025-08-24 12:09:20', 1, '2025-08-24 12:09:20', 3000, 'ESP32-RFID-Scanner', 'active'),
(30, '69:33:b2:01', 'TFVQ4NJU', NULL, 1, 5, '2025-08-17 18:12:10', '2025-08-24 12:11:41', 1, '2025-08-24 12:11:41', 3000, 'ESP32-RFID-Scanner', 'active'),
(31, '22:b0:8f:c3', 'XXFTZ825', NULL, 2, 5, '2025-08-18 03:35:44', '2025-08-19 03:30:34', 1, '2025-08-18 13:07:19', 3000, 'ESP32-RFID-Scanner', 'active'),
(32, '11:7b:b0:01', '3UK88OKH', NULL, 3, 5, '2025-08-18 03:41:01', '2025-08-24 12:11:01', 1, '2025-08-24 12:11:01', 3000, 'ESP32-RFID-Scanner', 'active');

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
(1, 28, '53:89:08:02', 'YT7E4DB3', 3, NULL, '2025-08-22 19:00:35', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -70, 'approved', '2025-08-23 03:00:30', '2025-08-22 19:00:30', 'OK', NULL),
(2, 28, '53:89:08:02', 'GP9VDKV7', 1, NULL, '2025-08-22 19:03:07', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -54, 'approved', '2025-08-23 03:03:04', '2025-08-22 19:03:04', 'OK', NULL),
(3, 30, '69:33:b2:01', 'FYQHI4CT', 5, NULL, '2025-08-22 19:07:46', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -62, 'approved', '2025-08-23 03:07:46', '2025-08-22 19:07:46', 'OK', NULL),
(4, 30, '69:33:b2:01', 'PNJY3WN2', 1, NULL, '2025-08-22 19:07:57', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -60, 'approved', '2025-08-23 03:07:56', '2025-08-22 19:07:56', 'OK', NULL),
(5, 30, '69:33:b2:01', 'PNJY3WN2', 2, NULL, '2025-08-22 19:08:11', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -56, 'approved', '2025-08-23 03:08:07', '2025-08-22 19:08:07', 'OK', NULL),
(6, 30, '69:33:b2:01', 'PNJY3WN2', 3, NULL, '2025-08-22 19:08:21', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-23 03:08:21', '2025-08-22 19:08:21', 'OK', NULL),
(7, 27, '4c:3f:b6:01', 'YC09VZT8', 4, NULL, '2025-08-22 19:08:35', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -53, 'approved', '2025-08-23 03:08:30', '2025-08-22 19:08:30', 'OK', NULL),
(8, 27, '4c:3f:b6:01', 'YC09VZT8', 5, NULL, '2025-08-22 19:09:00', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -63, 'approved', '2025-08-23 03:08:57', '2025-08-22 19:08:57', 'OK', NULL),
(9, 27, '4c:3f:b6:01', '5XHLLBXO', 1, NULL, '2025-08-22 19:09:17', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -59, 'approved', '2025-08-23 03:09:09', '2025-08-22 19:09:09', 'OK', NULL),
(10, 29, 'c2:48:94:ab', 'VI5YOWDN', 2, NULL, '2025-08-22 19:18:43', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-23 03:18:43', '2025-08-22 19:18:43', 'OK', NULL),
(11, 29, 'c2:48:94:ab', 'VI5YOWDN', 3, NULL, '2025-08-22 19:18:54', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -64, 'approved', '2025-08-23 03:18:53', '2025-08-22 19:18:53', 'OK', NULL),
(12, 29, 'c2:48:94:ab', 'VI5YOWDN', 4, NULL, '2025-08-22 19:19:04', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -66, 'approved', '2025-08-23 03:19:03', '2025-08-22 19:19:03', 'OK', NULL),
(13, 29, 'c2:48:94:ab', 'VI5YOWDN', 5, NULL, '2025-08-22 19:19:52', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -59, 'approved', '2025-08-23 03:19:13', '2025-08-22 19:19:13', 'OK', NULL),
(14, 29, 'c2:48:94:ab', '4OTEOD1O', 2, NULL, '2025-08-22 19:19:52', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-23 03:19:49', '2025-08-22 19:19:49', 'OK', NULL),
(15, 29, 'c2:48:94:ab', '4OTEOD1O', 3, NULL, '2025-08-22 19:20:03', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -73, 'approved', '2025-08-23 03:20:03', '2025-08-22 19:20:03', 'OK', NULL),
(16, 29, 'c2:48:94:ab', '4OTEOD1O', 4, NULL, '2025-08-22 19:20:24', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-23 03:20:13', '2025-08-22 19:20:13', 'OK', NULL),
(17, 29, 'c2:48:94:ab', '4OTEOD1O', 5, NULL, '2025-08-22 19:20:33', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -62, 'approved', '2025-08-23 03:20:32', '2025-08-22 19:20:32', 'OK', NULL),
(18, 29, 'c2:48:94:ab', 'OPE4RF3R', 1, NULL, '2025-08-22 19:20:45', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -57, 'approved', '2025-08-23 03:20:42', '2025-08-22 19:20:42', 'OK', NULL),
(19, 29, 'c2:48:94:ab', 'OPE4RF3R', 2, NULL, '2025-08-22 19:23:54', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -48, 'approved', '2025-08-23 03:23:51', '2025-08-22 19:23:51', 'OK', NULL),
(20, 29, 'c2:48:94:ab', 'OPE4RF3R', 3, NULL, '2025-08-22 19:24:18', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -73, 'approved', '2025-08-23 03:24:17', '2025-08-22 19:24:17', 'OK', NULL),
(21, 29, 'c2:48:94:ab', 'OPE4RF3R', 5, NULL, '2025-08-22 19:25:04', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-23 03:25:00', '2025-08-22 19:25:00', 'OK', NULL),
(22, 30, '69:33:b2:01', 'PNJY3WN2', 4, NULL, '2025-08-23 19:00:14', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -59, 'approved', '2025-08-24 03:00:13', '2025-08-23 19:00:13', 'OK', NULL),
(23, 30, '69:33:b2:01', 'PNJY3WN2', 5, NULL, '2025-08-23 19:00:24', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 03:00:24', '2025-08-23 19:00:24', 'OK', NULL),
(24, 30, '69:33:b2:01', 'TJXYKJYU', 1, NULL, '2025-08-23 19:00:34', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -79, 'approved', '2025-08-24 03:00:34', '2025-08-23 19:00:34', 'OK', NULL),
(25, 30, '69:33:b2:01', 'TJXYKJYU', 2, NULL, '2025-08-23 19:00:51', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -62, 'approved', '2025-08-24 03:00:51', '2025-08-23 19:00:51', 'OK', NULL),
(26, 30, '69:33:b2:01', 'TJXYKJYU', 3, NULL, '2025-08-23 19:01:03', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -72, 'approved', '2025-08-24 03:01:01', '2025-08-23 19:01:01', 'OK', NULL),
(27, 30, '69:33:b2:01', 'TJXYKJYU', 4, NULL, '2025-08-23 19:01:14', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -55, 'approved', '2025-08-24 03:01:13', '2025-08-23 19:01:13', 'OK', NULL),
(28, 30, '69:33:b2:01', 'TJXYKJYU', 5, NULL, '2025-08-23 19:01:25', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -54, 'approved', '2025-08-24 03:01:24', '2025-08-23 19:01:24', 'OK', NULL),
(29, 30, '69:33:b2:01', 'W1BRPTAP', 1, NULL, '2025-08-23 19:01:37', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -74, 'approved', '2025-08-24 03:01:35', '2025-08-23 19:01:35', 'OK', NULL),
(30, 28, '53:89:08:02', 'GP9VDKV7', 2, NULL, '2025-08-23 19:02:17', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-24 03:02:11', '2025-08-23 19:02:11', 'OK', NULL),
(31, 28, '53:89:08:02', 'GP9VDKV7', 3, NULL, '2025-08-23 19:02:30', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -66, 'approved', '2025-08-24 03:02:27', '2025-08-23 19:02:27', 'OK', NULL),
(32, 28, '53:89:08:02', 'GP9VDKV7', 4, NULL, '2025-08-23 19:02:39', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -62, 'approved', '2025-08-24 03:02:40', '2025-08-23 19:02:40', 'OK', NULL),
(33, 28, '53:89:08:02', 'WDT9SNDG', 1, NULL, '2025-08-23 19:03:07', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -75, 'approved', '2025-08-24 03:03:04', '2025-08-23 19:03:04', 'OK', NULL),
(34, 28, '53:89:08:02', 'WDT9SNDG', 2, NULL, '2025-08-23 19:10:53', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -62, 'approved', '2025-08-24 03:10:53', '2025-08-23 19:10:53', 'OK', NULL),
(35, 28, '53:89:08:02', 'WDT9SNDG', 3, NULL, '2025-08-23 19:31:06', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -56, 'approved', '2025-08-24 03:31:05', '2025-08-23 19:31:05', 'OK', NULL),
(36, 28, '53:89:08:02', 'WDT9SNDG', 4, NULL, '2025-08-23 19:31:17', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -54, 'approved', '2025-08-24 03:31:16', '2025-08-23 19:31:16', 'OK', NULL),
(37, 28, '53:89:08:02', 'WDT9SNDG', 5, NULL, '2025-08-23 19:31:30', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -53, 'approved', '2025-08-24 03:31:27', '2025-08-23 19:31:27', 'OK', NULL),
(38, 28, '53:89:08:02', '4VCKU0HP', 1, NULL, '2025-08-23 19:31:42', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -55, 'approved', '2025-08-24 03:31:40', '2025-08-23 19:31:40', 'OK', NULL),
(39, 27, '4c:3f:b6:01', '5XHLLBXO', 2, NULL, '2025-08-24 08:56:56', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -54, 'approved', '2025-08-24 16:56:55', '2025-08-24 08:56:55', 'OK', NULL),
(40, 28, '53:89:08:02', '4VCKU0HP', 2, NULL, '2025-08-24 09:15:21', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -71, 'approved', '2025-08-24 17:15:20', '2025-08-24 09:15:20', 'OK', NULL),
(41, 28, '53:89:08:02', '4VCKU0HP', 3, NULL, '2025-08-24 09:15:42', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -70, 'approved', '2025-08-24 17:15:41', '2025-08-24 09:15:41', 'OK', NULL),
(42, 29, 'c2:48:94:ab', '5GN3U591', 1, NULL, '2025-08-24 09:18:20', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -57, 'approved', '2025-08-24 17:18:20', '2025-08-24 09:18:20', 'OK', NULL),
(43, 29, 'c2:48:94:ab', '5GN3U591', 2, NULL, '2025-08-24 09:21:19', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -71, 'approved', '2025-08-24 17:21:18', '2025-08-24 09:21:18', 'OK', NULL),
(44, 29, 'c2:48:94:ab', '5GN3U591', 3, NULL, '2025-08-24 09:21:29', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 17:21:29', '2025-08-24 09:21:29', 'OK', NULL),
(45, 27, '4c:3f:b6:01', '5XHLLBXO', 3, NULL, '2025-08-24 09:23:16', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -57, 'approved', '2025-08-24 17:23:15', '2025-08-24 09:23:15', 'OK', NULL),
(46, 27, '4c:3f:b6:01', '5XHLLBXO', 4, NULL, '2025-08-24 09:25:58', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-24 17:25:57', '2025-08-24 09:25:57', 'OK', NULL),
(47, 27, '4c:3f:b6:01', '5XHLLBXO', 5, NULL, '2025-08-24 09:26:08', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -57, 'approved', '2025-08-24 17:26:08', '2025-08-24 09:26:08', 'OK', NULL),
(48, 27, '4c:3f:b6:01', 'AVM7U0Z4', 1, NULL, '2025-08-24 09:26:19', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-24 17:26:18', '2025-08-24 09:26:18', 'OK', NULL),
(49, 27, '4c:3f:b6:01', 'AVM7U0Z4', 2, NULL, '2025-08-24 09:27:01', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -63, 'approved', '2025-08-24 17:26:58', '2025-08-24 09:26:58', 'OK', NULL),
(50, 32, '11:7b:b0:01', '8QIECDWW', 3, NULL, '2025-08-24 11:09:51', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -62, 'approved', '2025-08-24 19:09:47', '2025-08-24 11:09:47', 'OK', NULL),
(51, 32, '11:7b:b0:01', '8QIECDWW', 4, NULL, '2025-08-24 11:10:00', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:10:01', '2025-08-24 11:10:01', 'OK', NULL),
(52, 32, '11:7b:b0:01', '8QIECDWW', 5, NULL, '2025-08-24 11:10:13', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-24 19:10:10', '2025-08-24 11:10:10', 'OK', NULL),
(53, 32, '11:7b:b0:01', 'BBGM3AVP', 1, NULL, '2025-08-24 11:10:25', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-24 19:10:23', '2025-08-24 11:10:23', 'OK', NULL),
(54, 27, '4c:3f:b6:01', 'AVM7U0Z4', 4, NULL, '2025-08-24 11:11:08', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -52, 'approved', '2025-08-24 19:11:07', '2025-08-24 11:11:07', 'OK', NULL),
(55, 27, '4c:3f:b6:01', 'AVM7U0Z4', 5, NULL, '2025-08-24 11:11:27', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:11:18', '2025-08-24 11:11:18', 'OK', NULL),
(56, 27, '4c:3f:b6:01', 'EG0WX4DO', 1, NULL, '2025-08-24 11:11:35', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-24 19:11:33', '2025-08-24 11:11:33', 'OK', NULL),
(57, 30, '69:33:b2:01', 'W1BRPTAP', 2, NULL, '2025-08-24 11:15:07', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -70, 'approved', '2025-08-24 19:15:07', '2025-08-24 11:15:07', 'OK', NULL),
(58, 30, '69:33:b2:01', 'W1BRPTAP', 3, NULL, '2025-08-24 11:15:25', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -64, 'approved', '2025-08-24 19:15:21', '2025-08-24 11:15:21', 'OK', NULL),
(59, 30, '69:33:b2:01', 'W1BRPTAP', 4, NULL, '2025-08-24 11:15:41', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-24 19:15:41', '2025-08-24 11:15:41', 'OK', NULL),
(60, 30, '69:33:b2:01', 'W1BRPTAP', 5, NULL, '2025-08-24 11:15:57', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -64, 'approved', '2025-08-24 19:15:51', '2025-08-24 11:15:51', 'OK', NULL),
(61, 30, '69:33:b2:01', 'JONW1UYI', 1, NULL, '2025-08-24 11:16:08', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -62, 'approved', '2025-08-24 19:16:07', '2025-08-24 11:16:07', 'OK', NULL),
(62, 32, '11:7b:b0:01', 'BBGM3AVP', 2, NULL, '2025-08-24 11:16:27', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -66, 'approved', '2025-08-24 19:16:26', '2025-08-24 11:16:26', 'OK', NULL),
(63, 32, '11:7b:b0:01', 'BBGM3AVP', 3, NULL, '2025-08-24 11:16:36', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -69, 'approved', '2025-08-24 19:16:37', '2025-08-24 11:16:37', 'OK', NULL),
(64, 32, '11:7b:b0:01', 'BBGM3AVP', 4, NULL, '2025-08-24 11:16:47', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:16:47', '2025-08-24 11:16:47', 'OK', NULL),
(65, 32, '11:7b:b0:01', 'BBGM3AVP', 5, NULL, '2025-08-24 11:17:20', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -57, 'approved', '2025-08-24 19:17:19', '2025-08-24 11:17:19', 'OK', NULL),
(66, 30, '69:33:b2:01', 'JONW1UYI', 2, NULL, '2025-08-24 11:18:12', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-24 19:18:10', '2025-08-24 11:18:10', 'OK', NULL),
(67, 30, '69:33:b2:01', 'JONW1UYI', 3, NULL, '2025-08-24 11:18:27', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:18:24', '2025-08-24 11:18:24', 'OK', NULL),
(68, 30, '69:33:b2:01', 'JONW1UYI', 4, NULL, '2025-08-24 11:18:37', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:18:37', '2025-08-24 11:18:37', 'OK', NULL),
(69, 30, '69:33:b2:01', 'JONW1UYI', 5, NULL, '2025-08-24 11:18:48', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -70, 'approved', '2025-08-24 19:18:48', '2025-08-24 11:18:48', 'OK', NULL),
(70, 30, '69:33:b2:01', 'CNJU940J', 1, NULL, '2025-08-24 11:18:58', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -56, 'approved', '2025-08-24 19:18:58', '2025-08-24 11:18:58', 'OK', NULL),
(71, 28, '53:89:08:02', '4VCKU0HP', 4, NULL, '2025-08-24 11:21:31', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:21:31', '2025-08-24 11:21:31', 'OK', NULL),
(72, 28, '53:89:08:02', '4VCKU0HP', 5, NULL, '2025-08-24 11:21:46', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-24 19:21:43', '2025-08-24 11:21:43', 'OK', NULL),
(73, 28, '53:89:08:02', 'DPHJS82Z', 1, NULL, '2025-08-24 11:22:34', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -66, 'approved', '2025-08-24 19:22:31', '2025-08-24 11:22:31', 'OK', NULL),
(74, 32, '11:7b:b0:01', '5UCHCNPN', 2, NULL, '2025-08-24 11:29:25', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:29:25', '2025-08-24 11:29:25', 'OK', NULL),
(75, 28, '53:89:08:02', 'DPHJS82Z', 2, NULL, '2025-08-24 11:29:38', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -79, 'approved', '2025-08-24 19:29:35', '2025-08-24 11:29:35', 'OK', NULL),
(76, 30, '69:33:b2:01', 'CNJU940J', 2, NULL, '2025-08-24 11:29:54', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:29:55', '2025-08-24 11:29:55', 'OK', NULL),
(77, 30, '69:33:b2:01', 'CNJU940J', 3, NULL, '2025-08-24 11:30:07', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -64, 'approved', '2025-08-24 19:30:05', '2025-08-24 11:30:05', 'OK', NULL),
(78, 30, '69:33:b2:01', 'CNJU940J', 4, NULL, '2025-08-24 11:30:22', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -57, 'approved', '2025-08-24 19:30:23', '2025-08-24 11:30:23', 'OK', NULL),
(79, 30, '69:33:b2:01', 'CNJU940J', 5, NULL, '2025-08-24 11:30:33', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -75, 'approved', '2025-08-24 19:30:34', '2025-08-24 11:30:34', 'OK', NULL),
(80, 30, '69:33:b2:01', '99BLCIFQ', 1, NULL, '2025-08-24 11:30:45', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-24 19:30:45', '2025-08-24 11:30:45', 'OK', NULL),
(81, 32, '11:7b:b0:01', '5UCHCNPN', 3, NULL, '2025-08-24 11:31:15', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:31:15', '2025-08-24 11:31:15', 'OK', NULL),
(82, 32, '11:7b:b0:01', '5UCHCNPN', 4, NULL, '2025-08-24 11:31:25', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -64, 'approved', '2025-08-24 19:31:25', '2025-08-24 11:31:25', 'OK', NULL),
(83, 32, '11:7b:b0:01', '5UCHCNPN', 5, NULL, '2025-08-24 11:31:35', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-24 19:31:35', '2025-08-24 11:31:35', 'OK', NULL),
(84, 32, '11:7b:b0:01', 'IPN0ZR5L', 1, NULL, '2025-08-24 11:31:44', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -55, 'approved', '2025-08-24 19:31:45', '2025-08-24 11:31:45', 'OK', NULL),
(85, 32, '11:7b:b0:01', 'IPN0ZR5L', 2, NULL, '2025-08-24 11:31:54', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -52, 'approved', '2025-08-24 19:31:54', '2025-08-24 11:31:54', 'OK', NULL),
(86, 27, '4c:3f:b6:01', 'EG0WX4DO', 2, NULL, '2025-08-24 11:32:05', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -56, 'approved', '2025-08-24 19:32:06', '2025-08-24 11:32:06', 'OK', NULL),
(87, 27, '4c:3f:b6:01', 'EG0WX4DO', 3, NULL, '2025-08-24 11:32:17', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -67, 'approved', '2025-08-24 19:32:18', '2025-08-24 11:32:18', 'OK', NULL),
(88, 27, '4c:3f:b6:01', 'EG0WX4DO', 4, NULL, '2025-08-24 11:32:27', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -61, 'approved', '2025-08-24 19:32:27', '2025-08-24 11:32:27', 'OK', NULL),
(89, 27, '4c:3f:b6:01', 'EG0WX4DO', 5, NULL, '2025-08-24 11:32:36', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -69, 'approved', '2025-08-24 19:32:37', '2025-08-24 11:32:37', 'OK', NULL),
(90, 27, '4c:3f:b6:01', '55MS62AZ', 1, NULL, '2025-08-24 11:32:51', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -58, 'approved', '2025-08-24 19:32:48', '2025-08-24 11:32:48', 'OK', NULL),
(91, 27, '4c:3f:b6:01', '55MS62AZ', 2, NULL, '2025-08-24 11:38:09', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -76, 'approved', '2025-08-24 19:38:08', '2025-08-24 11:38:08', 'OK', NULL),
(92, 27, '4c:3f:b6:01', '55MS62AZ', 3, NULL, '2025-08-24 11:38:44', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -61, 'approved', '2025-08-24 19:38:44', '2025-08-24 11:38:44', 'OK', NULL),
(93, 27, '4c:3f:b6:01', '55MS62AZ', 4, NULL, '2025-08-24 11:38:54', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -61, 'approved', '2025-08-24 19:38:54', '2025-08-24 11:38:54', 'OK', NULL),
(94, 27, '4c:3f:b6:01', '55MS62AZ', 5, NULL, '2025-08-24 11:39:10', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -65, 'approved', '2025-08-24 19:39:04', '2025-08-24 11:39:04', 'OK', NULL),
(95, 27, '4c:3f:b6:01', '18MG8OEF', 1, NULL, '2025-08-24 11:39:20', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -56, 'approved', '2025-08-24 19:39:20', '2025-08-24 11:39:20', 'OK', NULL),
(96, 28, '53:89:08:02', 'DPHJS82Z', 3, NULL, '2025-08-24 11:47:08', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -61, 'approved', '2025-08-24 19:47:09', '2025-08-24 11:47:09', 'OK', NULL),
(97, 28, '53:89:08:02', 'DPHJS82Z', 4, NULL, '2025-08-24 11:47:28', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -74, 'approved', '2025-08-24 19:47:28', '2025-08-24 11:47:28', 'OK', NULL),
(98, 28, '53:89:08:02', 'DPHJS82Z', 5, NULL, '2025-08-24 11:47:37', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -91, 'approved', '2025-08-24 19:47:38', '2025-08-24 11:47:38', 'OK', NULL),
(99, 28, '53:89:08:02', 'ZKAISC8V', 1, NULL, '2025-08-24 11:47:54', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -59, 'approved', '2025-08-24 19:47:54', '2025-08-24 11:47:54', 'OK', NULL),
(100, 28, '53:89:08:02', 'ZKAISC8V', 2, NULL, '2025-08-24 12:03:06', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -56, 'approved', '2025-08-24 20:03:06', '2025-08-24 12:03:06', 'OK', NULL),
(101, 28, '53:89:08:02', 'ZKAISC8V', 3, NULL, '2025-08-24 12:03:54', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -64, 'approved', '2025-08-24 20:03:52', '2025-08-24 12:03:52', 'OK', NULL),
(102, 30, '69:33:b2:01', '99BLCIFQ', 2, NULL, '2025-08-24 12:04:05', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-24 20:04:05', '2025-08-24 12:04:05', 'OK', NULL),
(103, 27, '4c:3f:b6:01', '18MG8OEF', 2, NULL, '2025-08-24 12:04:40', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -70, 'approved', '2025-08-24 20:04:40', '2025-08-24 12:04:40', 'OK', NULL),
(104, 29, 'c2:48:94:ab', '5GN3U591', 4, NULL, '2025-08-24 12:05:19', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -59, 'approved', '2025-08-24 20:05:19', '2025-08-24 12:05:19', 'OK', NULL),
(105, 32, '11:7b:b0:01', 'IPN0ZR5L', 3, NULL, '2025-08-24 12:06:46', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -64, 'approved', '2025-08-24 20:06:46', '2025-08-24 12:06:46', 'OK', NULL),
(106, 32, '11:7b:b0:01', 'IPN0ZR5L', 4, NULL, '2025-08-24 12:07:01', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -62, 'approved', '2025-08-24 20:07:01', '2025-08-24 12:07:01', 'OK', NULL),
(107, 29, 'c2:48:94:ab', '5GN3U591', 5, NULL, '2025-08-24 12:07:33', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -56, 'approved', '2025-08-24 20:07:33', '2025-08-24 12:07:33', 'OK', NULL),
(108, 29, 'c2:48:94:ab', 'EZSRFAII', 1, NULL, '2025-08-24 12:08:08', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -76, 'approved', '2025-08-24 20:08:08', '2025-08-24 12:08:08', 'OK', NULL),
(109, 29, 'c2:48:94:ab', 'EZSRFAII', 2, NULL, '2025-08-24 12:09:20', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -67, 'approved', '2025-08-24 20:09:20', '2025-08-24 12:09:20', 'OK', NULL),
(110, 28, '53:89:08:02', 'ZKAISC8V', 4, NULL, '2025-08-24 12:09:39', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -75, 'approved', '2025-08-24 20:09:40', '2025-08-24 12:09:40', 'OK', NULL),
(111, 32, '11:7b:b0:01', 'IPN0ZR5L', 5, NULL, '2025-08-24 12:09:49', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -64, 'approved', '2025-08-24 20:09:49', '2025-08-24 12:09:49', 'OK', NULL),
(112, 32, '11:7b:b0:01', '3UK88OKH', 1, NULL, '2025-08-24 12:10:19', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-24 20:10:19', '2025-08-24 12:10:19', 'OK', NULL),
(113, 32, '11:7b:b0:01', '3UK88OKH', 2, NULL, '2025-08-24 12:10:29', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -68, 'approved', '2025-08-24 20:10:29', '2025-08-24 12:10:29', 'OK', NULL),
(114, 32, '11:7b:b0:01', '3UK88OKH', 3, NULL, '2025-08-24 12:11:01', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -66, 'approved', '2025-08-24 20:11:02', '2025-08-24 12:11:02', 'OK', NULL),
(115, 30, '69:33:b2:01', '99BLCIFQ', 3, NULL, '2025-08-24 12:11:11', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -75, 'approved', '2025-08-24 20:11:11', '2025-08-24 12:11:11', 'OK', NULL),
(116, 30, '69:33:b2:01', '99BLCIFQ', 4, NULL, '2025-08-24 12:11:21', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -76, 'approved', '2025-08-24 20:11:21', '2025-08-24 12:11:21', 'OK', NULL),
(117, 30, '69:33:b2:01', '99BLCIFQ', 5, NULL, '2025-08-24 12:11:31', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -66, 'approved', '2025-08-24 20:11:31', '2025-08-24 12:11:31', 'OK', NULL),
(118, 30, '69:33:b2:01', 'TFVQ4NJU', 1, NULL, '2025-08-24 12:11:41', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -61, 'approved', '2025-08-24 20:11:42', '2025-08-24 12:11:42', 'OK', NULL),
(119, 27, '4c:3f:b6:01', '18MG8OEF', 3, NULL, '2025-08-24 12:12:12', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -87, 'approved', '2025-08-24 20:12:12', '2025-08-24 12:12:12', 'OK', NULL),
(120, 27, '4c:3f:b6:01', '18MG8OEF', 4, NULL, '2025-08-24 12:12:21', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -83, 'approved', '2025-08-24 20:12:22', '2025-08-24 12:12:22', 'OK', NULL),
(121, 27, '4c:3f:b6:01', '18MG8OEF', 5, NULL, '2025-08-24 12:12:31', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -72, 'approved', '2025-08-24 20:12:31', '2025-08-24 12:12:31', 'OK', NULL),
(122, 27, '4c:3f:b6:01', '3ECMH79O', 1, NULL, '2025-08-24 12:12:45', 'ESP32-RFID-Scanner', 'HUAWEI-2.4G-x6Nj', -79, 'approved', '2025-08-24 20:12:41', '2025-08-24 12:12:41', 'OK', NULL);

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
-- Table structure for table `services2`
--

CREATE TABLE `services2` (
  `id` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `category` enum('basic','premium','addon') DEFAULT 'basic',
  `base_price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `is_size_based` tinyint(1) DEFAULT 1,
  `status` enum('active','inactive') DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `services2`
--

INSERT INTO `services2` (`id`, `name`, `description`, `category`, `base_price`, `is_size_based`, `status`, `created_at`, `updated_at`) VALUES
(1, 'Basic Bath', 'Shampoo, rinse, and basic dry', 'basic', 300.00, 1, 'active', '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(2, 'Nail Trimming', 'Professional nail care', 'basic', 150.00, 1, 'active', '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(3, 'Ear Cleaning', 'Safe ear cleaning and inspection', 'basic', 200.00, 0, 'active', '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(4, 'Full Grooming Package', 'Bath, cut, style, nails, ears, and teeth', 'premium', 650.00, 1, 'active', '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(5, 'Dental Care', 'Teeth cleaning and oral health check', 'premium', 250.00, 1, 'active', '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(6, 'De-shedding Treatment', 'Reduces shedding up to 90%', 'premium', 425.00, 1, 'active', '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(7, 'Nail Polish', 'Pet-safe nail colors', 'addon', 100.00, 0, 'active', '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(8, 'Perfume & Bow', 'Finishing touches for a perfect look', 'addon', 150.00, 0, 'active', '2025-08-24 10:20:33', '2025-08-24 10:20:33');

-- --------------------------------------------------------

--
-- Table structure for table `service_pricing`
--

CREATE TABLE `service_pricing` (
  `id` int(11) NOT NULL,
  `service_id` int(11) NOT NULL,
  `pet_size` enum('small','medium','large','extra_large') NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `service_pricing`
--

INSERT INTO `service_pricing` (`id`, `service_id`, `pet_size`, `price`, `created_at`, `updated_at`) VALUES
(1, 1, 'small', 250.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(2, 1, 'medium', 300.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(3, 1, 'large', 350.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(4, 1, 'extra_large', 400.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(5, 2, 'small', 120.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(6, 2, 'medium', 150.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(7, 2, 'large', 180.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(8, 2, 'extra_large', 200.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(9, 3, 'small', 200.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(10, 3, 'medium', 200.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(11, 3, 'large', 200.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(12, 3, 'extra_large', 200.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(13, 4, 'small', 500.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(14, 4, 'medium', 600.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(15, 4, 'large', 750.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(16, 4, 'extra_large', 900.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(17, 5, 'small', 200.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(18, 5, 'medium', 250.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(19, 5, 'large', 280.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(20, 5, 'extra_large', 300.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(21, 6, 'small', 350.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(22, 6, 'medium', 400.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(23, 6, 'large', 450.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(24, 6, 'extra_large', 500.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(25, 7, 'small', 100.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(26, 7, 'medium', 100.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(27, 7, 'large', 100.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(28, 7, 'extra_large', 100.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(29, 8, 'small', 150.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(30, 8, 'medium', 150.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(31, 8, 'large', 150.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33'),
(32, 8, 'extra_large', 150.00, '2025-08-24 10:20:33', '2025-08-24 10:20:33');

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
(265, 83, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-19 05:58:05'),
(266, 87, 'checked-in', 'Initial check-in completed', NULL, '2025-08-22 19:13:54'),
(267, 88, 'checked-in', 'Initial check-in completed', NULL, '2025-08-22 19:20:50'),
(268, 88, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-22 19:23:54'),
(269, 88, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-22 19:24:18'),
(270, 88, 'completed', 'Service completed! Pet picked up via RFID tap #5', 'RFID System', '2025-08-22 19:25:04'),
(271, 89, 'checked-in', 'Initial check-in completed', NULL, '2025-08-23 19:03:14'),
(272, 89, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-23 19:10:53'),
(273, 89, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-23 19:30:50'),
(274, 89, 'ready', 'Status updated via RFID tap', NULL, '2025-08-23 19:30:52'),
(275, 89, 'completed', 'Status updated via RFID tap', NULL, '2025-08-23 19:30:55'),
(276, 90, 'checked-in', 'Initial check-in completed', NULL, '2025-08-23 19:31:45'),
(277, 87, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-24 08:56:56'),
(278, 90, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-24 09:15:21'),
(279, 90, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-24 09:15:42'),
(280, 87, 'grooming', 'Status automatically updated via RFID tap #3', 'RFID System', '2025-08-24 09:23:16'),
(281, 87, 'ready', 'Status updated via RFID tap', NULL, '2025-08-24 09:25:44'),
(282, 87, 'completed', 'Status updated via RFID tap', NULL, '2025-08-24 09:25:46'),
(283, 91, 'checked-in', 'Initial check-in completed', NULL, '2025-08-24 09:26:24'),
(284, 91, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-24 09:27:01'),
(285, 91, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-24 09:33:08'),
(286, 91, 'ready', 'Status updated via RFID tap', NULL, '2025-08-24 09:33:10'),
(287, 91, 'completed', 'Status updated via RFID tap', NULL, '2025-08-24 09:33:15'),
(288, 92, 'checked-in', 'Initial check-in completed', NULL, '2025-08-24 11:11:40'),
(289, 90, 'ready', 'Status automatically updated via RFID tap #4', 'RFID System', '2025-08-24 11:21:31'),
(290, 90, 'completed', 'Status updated via RFID tap', NULL, '2025-08-24 11:21:32'),
(291, 93, 'checked-in', 'Initial check-in completed', NULL, '2025-08-24 11:22:41'),
(292, 93, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-24 11:29:38'),
(293, 93, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-24 11:29:40'),
(294, 93, 'ready', 'Status updated via RFID tap', NULL, '2025-08-24 11:29:42'),
(295, 93, 'completed', 'Status updated via RFID tap', NULL, '2025-08-24 11:29:44'),
(296, 92, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-24 11:32:05'),
(297, 92, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-24 11:32:06'),
(298, 92, 'ready', 'Status updated via RFID tap', NULL, '2025-08-24 11:32:08'),
(299, 92, 'completed', 'Status updated via RFID tap', NULL, '2025-08-24 11:32:10'),
(300, 94, 'checked-in', 'Initial check-in completed', NULL, '2025-08-24 11:32:56'),
(301, 94, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-24 11:38:09'),
(302, 94, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-24 11:38:09'),
(303, 94, 'ready', 'Status updated via RFID tap', NULL, '2025-08-24 11:38:11'),
(304, 94, 'completed', 'Status updated via RFID tap', NULL, '2025-08-24 11:38:13'),
(305, 95, 'checked-in', 'Initial check-in completed', NULL, '2025-08-24 11:39:25'),
(306, 96, 'checked-in', 'Initial check-in completed', NULL, '2025-08-24 11:48:00'),
(307, 96, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-24 12:03:06'),
(308, 96, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-24 12:03:07'),
(309, 96, 'ready', 'Status updated via RFID tap', NULL, '2025-08-24 12:03:09'),
(310, 96, 'completed', 'Status updated via RFID tap', NULL, '2025-08-24 12:03:11'),
(311, 95, 'bathing', 'Status automatically updated via RFID tap #2', 'RFID System', '2025-08-24 12:04:40'),
(312, 95, 'grooming', 'Status updated via RFID tap', NULL, '2025-08-24 12:04:41'),
(313, 95, 'ready', 'Status updated via RFID tap', NULL, '2025-08-24 12:04:43'),
(314, 95, 'completed', 'Status updated via RFID tap', NULL, '2025-08-24 12:04:45'),
(315, 97, 'checked-in', 'Initial check-in completed', NULL, '2025-08-24 12:14:29');

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
-- Structure for view `booking_rfid_view`
--
DROP TABLE IF EXISTS `booking_rfid_view`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `booking_rfid_view`  AS SELECT `b`.`id` AS `booking_id`, `b`.`custom_rfid` AS `custom_rfid`, `b`.`status` AS `status`, `b`.`total_amount` AS `total_amount`, `b`.`check_in_time` AS `check_in_time`, `b`.`estimated_completion` AS `estimated_completion`, `b`.`actual_completion` AS `actual_completion`, `p`.`name` AS `pet_name`, `p`.`type` AS `pet_type`, `p`.`breed` AS `pet_breed`, `c`.`name` AS `owner_name`, `c`.`phone` AS `owner_phone`, `c`.`email` AS `owner_email`, `rc`.`tap_count` AS `tap_count`, `rc`.`max_taps` AS `max_taps`, `rc`.`card_uid` AS `card_uid`, CASE WHEN `b`.`status` = 'checked-in' THEN 'Waiting for first service' WHEN `b`.`status` = 'bathing' THEN 'Currently bathing' WHEN `b`.`status` = 'grooming' THEN 'Currently grooming' WHEN `b`.`status` = 'ready' THEN 'Ready for pickup' WHEN `b`.`status` = 'completed' THEN 'Completed' ELSE 'Unknown status' END AS `status_description` FROM (((`bookings` `b` left join `pets` `p` on(`b`.`pet_id` = `p`.`id`)) left join `customers` `c` on(`p`.`customer_id` = `c`.`id`)) left join `rfid_cards` `rc` on(`b`.`custom_rfid` = `rc`.`custom_uid`)) WHERE `b`.`custom_rfid` is not null ;

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
  ADD KEY `service_id` (`service_id`),
  ADD KEY `idx_booking_services_size` (`pet_size`);

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
-- Indexes for table `pet_sizes`
--
ALTER TABLE `pet_sizes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `size_code` (`size_code`);

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
-- Indexes for table `services2`
--
ALTER TABLE `services2`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_service_name` (`name`);

--
-- Indexes for table `service_pricing`
--
ALTER TABLE `service_pricing`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_service_size` (`service_id`,`pet_size`);

--
-- Indexes for table `status_updates`
--
ALTER TABLE `status_updates`
  ADD PRIMARY KEY (`id`),
  ADD KEY `booking_id` (`booking_id`),
  ADD KEY `idx_booking_created` (`booking_id`,`created_at`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `bookings`
--
ALTER TABLE `bookings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=98;

--
-- AUTO_INCREMENT for table `booking_services`
--
ALTER TABLE `booking_services`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=266;

--
-- AUTO_INCREMENT for table `customers`
--
ALTER TABLE `customers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=38;

--
-- AUTO_INCREMENT for table `pets`
--
ALTER TABLE `pets`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=120;

--
-- AUTO_INCREMENT for table `pet_sizes`
--
ALTER TABLE `pet_sizes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `rfid_cards`
--
ALTER TABLE `rfid_cards`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=33;

--
-- AUTO_INCREMENT for table `rfid_tap_history`
--
ALTER TABLE `rfid_tap_history`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=123;

--
-- AUTO_INCREMENT for table `services`
--
ALTER TABLE `services`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `services2`
--
ALTER TABLE `services2`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `service_pricing`
--
ALTER TABLE `service_pricing`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=33;

--
-- AUTO_INCREMENT for table `status_updates`
--
ALTER TABLE `status_updates`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=316;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `service_pricing`
--
ALTER TABLE `service_pricing`
  ADD CONSTRAINT `service_pricing_ibfk_1` FOREIGN KEY (`service_id`) REFERENCES `services` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
