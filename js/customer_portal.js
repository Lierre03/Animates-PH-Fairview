// API base URL - adjust this to your server location
const API_BASE = 'http://localhost/animates/api/';

// Sample tracking data for demo (will be replaced with real API calls)
let trackingData = {};
let currentUser = null;

// Prevent back navigation without logout
window.history.pushState(null, "", window.location.href);
window.addEventListener('popstate', function (event) {
    // Check if user is authenticated before allowing navigation
    const token = localStorage.getItem('authToken');
    if (!token) {
        // If no token, redirect to auth
        redirectToAuth();
        return;
    }
    // If authenticated, push state again to prevent going back
    window.history.pushState(null, "", window.location.href);
    showNotification('Please use the logout button to exit', 'warning');
});

// Disable browser refresh and close shortcuts
document.addEventListener('keydown', function(e) {
    // Disable F5
    if (e.keyCode === 116) {
        e.preventDefault();
        showNotification('Please use the logout button to exit safely', 'warning');
        return false;
    }
    
    // Disable Ctrl+R
    if ((e.ctrlKey || e.metaKey) && e.keyCode === 82) {
        e.preventDefault();
        showNotification('Please use the logout button to exit safely', 'warning');
        return false;
    }
    
    // Disable Ctrl+W (close tab)
    if ((e.ctrlKey || e.metaKey) && e.keyCode === 87) {
        e.preventDefault();
        showNotification('Please use the logout button to exit safely', 'warning');
        return false;
    }
});

// Warn before page unload
window.addEventListener('beforeunload', function (e) {
    const token = localStorage.getItem('authToken');
    if (token) {
        e.preventDefault();
        e.returnValue = '';
        return 'Are you sure you want to leave? Please use the logout button to exit safely.';
    }
});

function showSection(sectionId) {
    // Hide all sections
    document.querySelectorAll('.section').forEach(section => {
        section.classList.add('hidden');
    });
    
    // Show selected section
    document.getElementById(sectionId).classList.remove('hidden');
    
    // Update desktop nav links
    document.querySelectorAll('.nav-link').forEach(link => {
        link.classList.remove('text-primary', 'font-semibold');
        link.classList.add('text-gray-700', 'font-medium');
    });
    
    // Update mobile nav links
    document.querySelectorAll('.mobile-nav-link').forEach(link => {
        link.classList.remove('text-primary', 'font-semibold');
        link.classList.add('text-gray-700', 'font-medium');
    });
    
    // Highlight active nav (desktop)
    const activeDesktopLink = document.querySelector(`[onclick="showSection('${sectionId}')"].nav-link`);
    if (activeDesktopLink) {
        activeDesktopLink.classList.remove('text-gray-700', 'font-medium');
        activeDesktopLink.classList.add('text-primary', 'font-semibold');
    }
    
    // Highlight active nav (mobile)
    const activeMobileLink = document.querySelector(`[onclick="showSection('${sectionId}')"].mobile-nav-link`);
    if (activeMobileLink) {
        activeMobileLink.classList.remove('text-gray-700', 'font-medium');
        activeMobileLink.classList.add('text-primary', 'font-semibold');
    }
}

function toggleMobileMenu() {
    const menu = document.getElementById('mobileMenu');
    menu.classList.toggle('hidden');
}

// Enhanced authentication and session management
async function checkAuth() {
    const token = localStorage.getItem('authToken');
    
    if (!token) {
        redirectToAuth();
        return false;
    }

    try {
        const response = await fetch(`${API_BASE}auth.php`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({ action: 'verify_token' })
        });

        const result = await response.json();
        
        if (result.success) {
            currentUser = {
                id: result.user_id,
                email: result.email
            };
            
            // Verify user has customer role
            const roleResponse = await fetch(`${API_BASE}auth.php`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                },
                body: JSON.stringify({ action: 'check_role' })
            });
            
            if (!roleResponse.ok) {
                throw new Error('Role verification failed');
            }
            
            updateUserWelcome();
            return true;
        } else {
            throw new Error('Token verification failed');
        }
    } catch (error) {
        console.error('Auth check failed:', error);
        localStorage.removeItem('authToken');
        redirectToAuth();
        return false;
    }
}

function updateUserWelcome() {
    const welcomeElement = document.getElementById('userWelcome');
    const welcomeMobileElement = document.getElementById('userWelcomeMobile');
    if (currentUser) {
        const welcomeText = `Welcome, ${currentUser.email}`;
        if (welcomeElement) welcomeElement.textContent = welcomeText;
        if (welcomeMobileElement) welcomeMobileElement.textContent = welcomeText;
    }
}

function redirectToAuth() {
    // Clear any stored data
    localStorage.clear();
    // Force redirect to auth page
    window.location.replace('auth.html');
}

async function logout() {
    try {
        const token = localStorage.getItem('authToken');
        
        if (token) {
            await fetch(`${API_BASE}logout.php`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${token}`
                }
            });
        }
        
        localStorage.clear();
        showNotification('Logged out successfully', 'success');
        
        setTimeout(() => {
            redirectToAuth();
        }, 1000);
        
    } catch (error) {
        console.error('Logout error:', error);
        localStorage.clear();
        redirectToAuth();
    }
}

// Updated pet tracking function for RFID search
async function trackPet() {
    const rfidInput = document.getElementById('rfidInput');
    const rfidValue = rfidInput.value.toUpperCase().trim();
    
    if (!rfidValue) {
        showNotification('Please enter an RFID tag ID.', 'warning');
        return;
    }

    try {
        showNotification('Tracking pet...', 'info');
        
        const token = localStorage.getItem('authToken');
        const response = await fetch(`${API_BASE}tracking.php?rfid=${rfidValue}`, {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
        const result = await response.json();
        
        if (result.success && result.data) {
            const petInfo = result.data;
            showNotification(`Found ${petInfo.pet_name}! Status: ${petInfo.status}`, 'success');
            
            // Display detailed tracking info
            displayPetTrackingInfo(petInfo);
        } else {
            showNotification('RFID tag not found or no active booking. Please check the ID and try again.', 'error');
        }
    } catch (error) {
        console.error('Error tracking pet:', error);
        showNotification('Error connecting to tracking system. Please try again.', 'error');
    }
    
    rfidInput.value = '';
}

function displayPetTrackingInfo(petInfo) {
    const container = document.getElementById('activeBookingsContainer');
    const statusSteps = {
        'checked-in': { step: 1, label: 'Checked In', color: 'green' },
        'bathing': { step: 2, label: 'Bathing', color: 'yellow' },
        'grooming': { step: 3, label: 'Grooming', color: 'yellow' },
        'ready': { step: 4, label: 'Ready for Pickup', color: 'green' }
    };
    
    const currentStatus = statusSteps[petInfo.status] || { step: 1, label: petInfo.status, color: 'gray' };
    
    container.innerHTML = `
        <div class="border border-gray-200 rounded-xl p-6">
            <div class="flex items-start justify-between mb-4">
                <div class="flex items-center space-x-3">
                    <div class="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center text-blue-600 text-xl">🐾</div>
                    <div>
                        <h3 class="font-semibold text-gray-900">${petInfo.pet_name}</h3>
                        <p class="text-sm text-gray-600">${petInfo.breed} • RFID: ${petInfo.tag_id}</p>
                        <p class="text-xs text-gray-500">Owner: ${petInfo.owner_name}</p>
                    </div>
                </div>
                <span class="px-3 py-1 bg-${currentStatus.color}-100 text-${currentStatus.color}-800 rounded-full text-sm font-medium">
                    ${currentStatus.label}
                </span>
            </div>
            
            <!-- Progress Timeline -->
            <div class="space-y-3 mb-4">
                ${generateTimelineSteps(petInfo.status, petInfo.status_history)}
            </div>

            <!-- Services -->
            <div class="mt-4 p-4 bg-gray-50 rounded-lg">
                <h4 class="font-medium text-gray-900 mb-2">Services</h4>
                <div class="space-y-1">
                    ${petInfo.services.map(service => `
                        <div class="flex justify-between text-sm">
                            <span>${service.name}</span>
                            <span>₱${service.price}</span>
                        </div>
                    `).join('')}
                </div>
                <div class="border-t mt-2 pt-2 flex justify-between font-semibold">
                    <span>Total:</span>
                    <span>₱${petInfo.total_amount}</span>
                </div>
            </div>

            <!-- Estimated Completion -->
            ${petInfo.estimated_completion ? `
                <div class="mt-4 p-4 bg-blue-50 rounded-lg">
                    <div class="flex justify-between items-center">
                        <span class="text-sm font-medium text-blue-700">Estimated Completion:</span>
                        <span class="text-sm font-bold text-blue-900">${formatTime(petInfo.estimated_completion)}</span>
                    </div>
                </div>
            ` : ''}
            
            <div class="mt-4 text-center">
                <button onclick="loadUserBookings()" class="text-primary hover:text-blue-700 text-sm font-medium">
                    ← Back to All Bookings
                </button>
            </div>
        </div>
    `;
}

// Updated function to load user's bookings automatically
async function loadUserBookings() {
    try {
        const token = localStorage.getItem('authToken');
        const response = await fetch(`${API_BASE}tracking.php`, {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
        const result = await response.json();
        
        if (result.success && result.data.length > 0) {
            document.getElementById('activeBookingsCount').textContent = result.data.length;
            displayAllActiveBookings(result.data);
        } else {
            document.getElementById('activeBookingsCount').textContent = '0';
            document.getElementById('activeBookingsContainer').innerHTML = `
                <div class="text-center py-8">
                    <div class="text-4xl mb-4">🐾</div>
                    <p class="text-gray-500">No active bookings found</p>
                    <p class="text-sm text-gray-400 mt-2">Your pets will appear here when they're being groomed</p>
                </div>
            `;
        }
    } catch (error) {
        console.error('Error loading user bookings:', error);
        if (error.message.includes('403') || error.message.includes('401')) {
            // Authentication issue, redirect to login
            redirectToAuth();
            return;
        }
        document.getElementById('activeBookingsContainer').innerHTML = `
            <div class="text-center py-8">
                <div class="text-4xl mb-4">⚠️</div>
                <p class="text-red-500">Error loading bookings</p>
                <p class="text-sm text-gray-500 mt-2">Please refresh the page or try again later</p>
            </div>
        `;
    }
}

function displayAllActiveBookings(bookings) {
    const container = document.getElementById('activeBookingsContainer');
    
    if (bookings.length === 0) {
        container.innerHTML = `
            <div class="text-center py-8">
                <div class="text-4xl mb-4">🐾</div>
                <p class="text-gray-500">No active bookings</p>
            </div>
        `;
        return;
    }
    
    container.innerHTML = `
    <div class="mb-4">
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Your Active Bookings</h3>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            ${bookings.map(booking => `
                <div class="border border-gray-200 rounded-xl p-6">
                    <div class="flex items-start justify-between mb-4">
                        <div class="flex items-center space-x-3">
                            <div class="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center text-blue-600 text-xl">🐾</div>
                            <div>
                                <h3 class="font-semibold text-gray-900">${booking.pet_name}</h3>
                                <p class="text-sm text-gray-600">${booking.breed} • ${booking.tag_id}</p>
                                <p class="text-xs text-gray-500">${booking.owner_name}</p>
                            </div>
                        </div>
                        <span class="px-3 py-1 ${getStatusColor(booking.status)} rounded-full text-sm font-medium">
                            ${booking.status.charAt(0).toUpperCase() + booking.status.slice(1).replace('-', ' ')}
                        </span>
                    </div>
                    <div class="text-center">
                        <button onclick="trackSpecificPet('${booking.tag_id}')" 
                                class="bg-primary hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors">
                            View Details
                        </button>
                    </div>
                </div>
            `).join('')}
        </div>
    </div>
`;
}

function getStatusColor(status) {
    const statusColors = {
        'checked-in': 'bg-blue-100 text-blue-800',
        'bathing': 'bg-purple-100 text-purple-800', 
        'grooming': 'bg-orange-100 text-orange-800',
        'ready': 'bg-green-100 text-green-800',
        'completed': 'bg-gray-100 text-gray-800'
    };
    
    return statusColors[status] || 'bg-yellow-100 text-yellow-800';
}

function getStatusColor(status) {
    const statusColors = {
        'checked-in': 'bg-blue-100 text-blue-800',
        'bathing': 'bg-purple-100 text-purple-800', 
        'grooming': 'bg-orange-100 text-orange-800',
        'ready': 'bg-green-100 text-green-800',
        'completed': 'bg-gray-100 text-gray-800'
    };
    
    return statusColors[status] || 'bg-yellow-100 text-yellow-800';
}

async function trackSpecificPet(rfidTag) {
    if (!rfidTag) {
        showNotification('Invalid RFID tag', 'warning');
        return;
    }

    try {
        showNotification('Loading pet details...', 'info');
        
        const token = localStorage.getItem('authToken');
        const response = await fetch(`${API_BASE}tracking.php?rfid=${rfidTag}`, {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
        const result = await response.json();
        
        if (result.success && result.data) {
            const petInfo = result.data;
            showNotification(`Found ${petInfo.pet_name}! Status: ${petInfo.status}`, 'success');
            
            // Display detailed tracking info
            displayPetTrackingInfo(petInfo);
        } else {
            showNotification('RFID tag not found or no active booking. Please check the ID and try again.', 'error');
        }
    } catch (error) {
        console.error('Error tracking pet:', error);
        showNotification('Error connecting to tracking system. Please try again.', 'error');
    }
}

function generateTimelineSteps(currentStatus, statusHistory) {
    const steps = [
        { key: 'checked-in', name: 'Check-in Complete', icon: '✓' },
        { key: 'bathing', name: 'Bathing', icon: '🛁' },
        { key: 'grooming', name: 'Grooming', icon: '✂️' },
        { key: 'ready', name: 'Ready for Pickup', icon: '✅' }
    ];
    
    const statusOrder = ['checked-in', 'bathing', 'grooming', 'ready'];
    const currentIndex = statusOrder.indexOf(currentStatus);
    
    return steps.map((step, index) => {
        const isCompleted = index <= currentIndex;
        const isCurrent = index === currentIndex;
        const statusInfo = statusHistory.find(h => h.status === step.key);
        
        return `
            <div class="flex items-center">
                <div class="w-6 h-6 ${isCompleted ? 'bg-green-500' : isCurrent ? 'bg-yellow-500' : 'bg-gray-300'} rounded-full flex items-center justify-center mr-3">
                    ${isCompleted ? 
                        '<svg class="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"></path></svg>' :
                        isCurrent ? '<div class="w-2 h-2 bg-white rounded-full animate-pulse"></div>' :
                        '<div class="w-2 h-2 bg-gray-500 rounded-full"></div>'
                    }
                </div>
                <div class="flex-1">
                    <p class="font-medium ${isCompleted ? 'text-gray-900' : 'text-gray-600'}">${step.name}</p>
                    ${statusInfo ? `<p class="text-sm text-gray-600">${formatTime(statusInfo.created_at)}</p>` : 
                     isCurrent ? '<p class="text-sm text-gray-600">In progress...</p>' :
                     '<p class="text-sm text-gray-500">Pending</p>'}
                </div>
            </div>
        `;
    }).join('');
}

function formatTime(timestamp) {
    const date = new Date(timestamp);
    return date.toLocaleTimeString('en-US', { 
        hour: 'numeric', 
        minute: '2-digit',
        hour12: true 
    });
}

// History filter function
function filterHistory(period) {
    // Update button styles
    event.target.parentElement.querySelectorAll('button').forEach(btn => {
        btn.classList.remove('bg-primary', 'text-white');
        btn.classList.add('bg-gray-200', 'text-gray-700');
    });
    
    event.target.classList.remove('bg-gray-200', 'text-gray-700');
    event.target.classList.add('bg-primary', 'text-white');
    
    showNotification(`History filter: ${period} (Feature coming soon)`, 'info');
}

// Notification system
function showNotification(message, type = 'info') {
    const notification = document.createElement('div');
    const colors = {
        success: 'bg-green-500',
        error: 'bg-red-500',
        warning: 'bg-yellow-500',
        info: 'bg-blue-500'
    };
    
    notification.className = `fixed top-4 right-4 ${colors[type]} text-white px-6 py-4 rounded-lg shadow-lg z-50 transform translate-x-full transition-transform duration-300`;
    notification.textContent = message;
    
    document.body.appendChild(notification);
    
    // Animate in
    setTimeout(() => {
        notification.classList.remove('translate-x-full');
    }, 100);
    
    // Remove after 4 seconds
    setTimeout(() => {
        notification.classList.add('translate-x-full');
        setTimeout(() => {
            notification.remove();
        }, 300);
    }, 4000);
}

// Initialize page
document.addEventListener('DOMContentLoaded', async function() {
    // Check authentication first
    const isAuthenticated = await checkAuth();
    if (!isAuthenticated) {
        return; // Stop execution if not authenticated
    }
    
    // Set tracking as default active section
    showSection('tracking');
    
    // Load user's bookings automatically
    loadUserBookings();
    
    // Add event listener to RFID input for Enter key (if it exists)
    const rfidInput = document.getElementById('rfidInput');
    if (rfidInput) {
        rfidInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                trackPet();
            }
        });
    }
    
// Auto-reload page every 30 seconds for real-time updates
setInterval(() => {
    // Only reload if we're on tracking section and showing all bookings
    if (!document.getElementById('tracking').classList.contains('hidden')) {
        const container = document.getElementById('activeBookingsContainer');
        if (container.innerHTML.includes('Your Active Bookings') || container.innerHTML.includes('No active bookings')) {
            showNotification('Refreshing for latest updates...', 'info');
            setTimeout(() => {
                window.location.href = window.location.href;
            }, 1000);
        }
    }
}, 30000);
});

// RFID Scanner Integration (for when you get the device)
function handleRFIDScan(tagId) {
    // This function will be called when RFID device detects a tag
    const rfidInput = document.getElementById('rfidInput');
    if (rfidInput) {
        rfidInput.value = tagId;
        trackPet();
    }
}









// Add these functions to your existing customer_portal.js file

// Initialize appointments section
async function initializeAppointments() {
    try {
        // Load staff members
        await loadStaffMembers();
        
        // Load services
        await loadServices();
        
        // Set minimum date to today
        setMinimumDate();
        
        // Initialize pet type change handler
        initializePetTypeHandler();
        
        // Initialize service selection handlers
        initializeServiceHandlers();
        
    } catch (error) {
        console.error('Error initializing appointments:', error);
        showNotification('Error loading appointment data', 'error');
    }
}

// Load staff members for preferred staff dropdown
async function loadStaffMembers() {
    try {
        const token = localStorage.getItem('authToken');
        const response = await fetch(`${API_BASE}appointments.php?action=get_staff`, {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
        
        const result = await response.json();
        
        if (result.success) {
            const staffSelect = document.querySelector('select[name="preferredStaff"]');
            if (staffSelect) {
                // Clear existing options except "No Preference"
                staffSelect.innerHTML = '<option value="">No Preference</option>';
                
                result.data.forEach(staff => {
                    const option = document.createElement('option');
                    option.value = staff.id;
                    option.textContent = `${staff.first_name} ${staff.last_name}`;
                    staffSelect.appendChild(option);
                });
            }
        }
    } catch (error) {
        console.error('Error loading staff members:', error);
    }
}

// Load services and populate service sections
async function loadServices() {
    try {
        const token = localStorage.getItem('authToken');
        const response = await fetch(`${API_BASE}appointments.php?action=get_services`, {
            headers: {
                'Authorization': `Bearer ${token}`
            }
        });
        
        const result = await response.json();
        
        if (result.success) {
            populateServices(result.data);
        }
    } catch (error) {
        console.error('Error loading services:', error);
    }
}

// Populate services in the form
function populateServices(services) {
    const basicServices = services.filter(s => s.category === 'basic');
    const premiumServices = services.filter(s => s.category === 'premium');
    const addonServices = services.filter(s => s.category === 'addon');
    
    // Populate basic services
    populateServiceSection('basicServices', basicServices);
    
    // Populate premium services  
    populateServiceSection('premiumServices', premiumServices);
    
    // Populate addon services
    populateServiceSection('addonServices', addonServices);
}

// Replace the existing populateServiceSection function with this updated version:
function populateServiceSection(containerId, services) {
    const container = document.getElementById(containerId);
    if (!container) return;
    
    const servicesContainer = container.querySelector('.space-y-4');
    if (!servicesContainer) return;
    
    servicesContainer.innerHTML = '';
    
    services.forEach(service => {
        const serviceHtml = `
            <label class="flex items-center p-4 bg-white/80 rounded-lg border border-blue-200 hover:border-blue-300 transition-all duration-200 cursor-pointer hover:shadow-md">
                <input type="checkbox" class="service-checkbox w-5 h-5 text-primary rounded" data-service="${service.name}" data-price="${service.price}" data-id="${service.id}">
                <div class="ml-4 flex-1 flex justify-between items-center">
                    <div>
                        <span class="font-medium text-gray-900">${service.name}</span>
                        ${service.description ? `<p class="text-sm text-gray-600">${service.description}</p>` : ''}
                    </div>
                    <span class="text-lg font-bold text-primary">₱${parseFloat(service.price).toFixed(2)}</span>
                </div>
            </label>
        `;
        servicesContainer.insertAdjacentHTML('beforeend', serviceHtml);
    });
}

// Set minimum date to today
function setMinimumDate() {
    const dateInput = document.querySelector('input[type="date"]');
    if (dateInput) {
        const today = new Date().toISOString().split('T')[0];
        dateInput.min = today;
    }
}

// Initialize pet type change handler
function initializePetTypeHandler() {
    const petTypeSelect = document.querySelector('select[name="petType"]');
    const petBreedSelect = document.querySelector('select[name="petBreed"]');
    
    if (!petTypeSelect || !petBreedSelect) return;
    
    petTypeSelect.addEventListener('change', async function() {
        const petType = this.value.toLowerCase();
        
        if (petType === 'others') {
            petBreedSelect.innerHTML = '<option value="">Enter breed manually</option>';
            petBreedSelect.disabled = true;
            // You might want to show a text input for custom breed here
        } else if (petType) {
            await loadBreeds(petType, petBreedSelect);
        } else {
            petBreedSelect.innerHTML = '<option value="">First select pet type</option>';
            petBreedSelect.disabled = true;
        }
    });
}

// Load breeds based on pet type (from check_in.js logic)
async function loadBreeds(petType, breedSelect) {
    try {
        breedSelect.innerHTML = '<option value="">Loading breeds...</option>';
        breedSelect.disabled = false;
        
        let apiUrl = '';
        if (petType === 'dog') {
            apiUrl = 'https://dog.ceo/api/breeds/list/all';
        } else if (petType === 'cat') {
            apiUrl = 'https://api.thecatapi.com/v1/breeds';
        }
        
        if (!apiUrl) {
            breedSelect.innerHTML = '<option value="">Select breed</option>';
            return;
        }
        
        const response = await fetch(apiUrl);
        const data = await response.json();
        
        breedSelect.innerHTML = '<option value="">Select breed</option>';
        
        if (petType === 'dog') {
            const breeds = Object.keys(data.message);
            breeds.forEach(breed => {
                const option = document.createElement('option');
                option.value = breed;
                option.textContent = breed.charAt(0).toUpperCase() + breed.slice(1);
                breedSelect.appendChild(option);
            });
        } else if (petType === 'cat') {
            data.forEach(breed => {
                const option = document.createElement('option');
                option.value = breed.name;
                option.textContent = breed.name;
                breedSelect.appendChild(option);
            });
        }
        
    } catch (error) {
        console.error('Error loading breeds:', error);
        breedSelect.innerHTML = '<option value="">Error loading breeds</option>';
    }
}

// Initialize service selection handlers
function initializeServiceHandlers() {
    document.addEventListener('change', function(e) {
        if (e.target.classList.contains('service-checkbox')) {
            updateAppointmentTotal();
        }
    });
}

// Replace the existing updateAppointmentTotal function:
function updateAppointmentTotal() {
    let total = 0;
    const checkedServices = document.querySelectorAll('.service-checkbox:checked');
    
    checkedServices.forEach(checkbox => {
        total += parseFloat(checkbox.dataset.price);
    });
    
    // Find the total element - it might be in different locations
    const totalElement = document.querySelector('.text-lg.font-bold.text-primary:last-child') || 
                        document.querySelector('#appointmentTotal') ||
                        document.querySelector('[class*="text-lg"][class*="font-bold"][class*="text-primary"]');
    
    if (totalElement) {
        totalElement.textContent = `₱${total.toFixed(2)}`;
    }
}



async function loadBreeds(petType, breedSelect) {
    try {
        breedSelect.innerHTML = '<option value="">Loading breeds...</option>';
        breedSelect.disabled = false;
        
        let apiUrl = '';
        if (petType === 'dog') {
            apiUrl = 'https://dog.ceo/api/breeds/list/all';
        } else if (petType === 'cat') {
            apiUrl = 'https://api.thecatapi.com/v1/breeds';
        }
        
        if (!apiUrl) {
            breedSelect.innerHTML = '<option value="">Select breed</option>';
            return;
        }
        
        const response = await fetch(apiUrl);
        const data = await response.json();
        
        breedSelect.innerHTML = '<option value="">Select breed</option>';
        
        if (petType === 'dog') {
            const breeds = Object.keys(data.message);
            breeds.sort().forEach(breed => {
                const option = document.createElement('option');
                option.value = breed;
                option.textContent = breed.charAt(0).toUpperCase() + breed.slice(1).replace(/[-_]/g, ' ');
                breedSelect.appendChild(option);
            });
        } else if (petType === 'cat') {
            data.sort((a, b) => a.name.localeCompare(b.name)).forEach(breed => {
                const option = document.createElement('option');
                option.value = breed.name;
                option.textContent = breed.name;
                breedSelect.appendChild(option);
            });
        }
        
    } catch (error) {
        console.error('Error loading breeds:', error);
        breedSelect.innerHTML = '<option value="">Error loading breeds</option>';
    }
}

// Handle appointment form submission
async function handleAppointmentSubmission(event) {
    event.preventDefault();
    
    const form = event.target;
    const formData = new FormData(form);
    
    // Validate required fields
    const petName = formData.get('petName');
    const petType = formData.get('petType');
    const petBreed = formData.get('petBreed');
    const preferredDate = formData.get('preferredDate');
    const preferredTime = formData.get('preferredTime');
    
    if (!petName || !petType || !petBreed || !preferredDate || !preferredTime) {
        showNotification('Please fill in all required fields', 'warning');
        return;
    }
    
    // Get selected services
    const selectedServices = [];
    document.querySelectorAll('.service-checkbox:checked').forEach(checkbox => {
        selectedServices.push(parseInt(checkbox.dataset.id));
    });
    
    if (selectedServices.length === 0) {
        showNotification('Please select at least one service', 'warning');
        return;
    }
    
    try {
        const token = localStorage.getItem('authToken');
        
        showNotification('Booking appointment...', 'info');
        
        const appointmentData = {
            action: 'book_appointment',
            petName: petName,
            petType: petType,
            petBreed: petBreed,
            petAge: formData.get('petAge'),
            petSize: formData.get('petSize'),
            preferredDate: preferredDate,
            preferredTime: preferredTime,
            preferredStaff: formData.get('preferredStaff'),
            services: selectedServices,
            specialInstructions: formData.get('specialInstructions')
        };
        
        const response = await fetch(`${API_BASE}appointments.php`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify(appointmentData)
        });
        
        const result = await response.json();
        
        if (result.success) {
            showNotification('Appointment booked successfully!', 'success');
            
            // Reset form
            form.reset();
            document.querySelectorAll('.service-checkbox').forEach(cb => cb.checked = false);
            updateAppointmentTotal();
            
            // Optionally switch to tracking section
            setTimeout(() => {
                showSection('tracking');
            }, 2000);
            
        } else {
            throw new Error(result.error || 'Failed to book appointment');
        }
        
    } catch (error) {
        console.error('Error booking appointment:', error);
        showNotification('Error booking appointment: ' + error.message, 'error');
    }
}

// Add this to your DOMContentLoaded event listener in customer_portal.js
document.addEventListener('DOMContentLoaded', async function() {
    // ... existing code ...
    
    // Initialize appointments when page loads
    await initializeAppointments();
    
    // Add form submission handler
    const appointmentForm = document.querySelector('#appointment form');
    if (appointmentForm) {
        appointmentForm.addEventListener('submit', handleAppointmentSubmission);
    }
    
    // ... rest of existing code ...
});