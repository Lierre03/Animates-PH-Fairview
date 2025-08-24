// Guest Dashboard JavaScript
let refreshInterval = null;
let currentBookingData = null;
let trackingToken = null;
let lastKnownStatus = null;

// API base URL
const API_BASE = 'http://localhost/animates/api/';


const statusConfig = {
    'checked-in': {
        label: 'Checked In',
        icon: 'fa-clipboard-check',
        color: 'blue',
        progress: 20,
        description: 'Your pet has been checked in and is waiting for services'
    },
    'bathing': {
        label: 'Bathing',
        icon: 'fa-bath',
        color: 'indigo',
        progress: 40,
        description: 'Your pet is currently being bathed and pampered'
    },
    'grooming': {
        label: 'Grooming',
        icon: 'fa-scissors',
        color: 'purple',
        progress: 60,
        description: 'Professional grooming services in progress'
    },
    'ready': {
        label: 'Ready for Pickup',
        icon: 'fa-bell',
        color: 'green',
        progress: 80,
        description: 'Your pet is ready! Please come for pickup'
    },
    'completed': {
        label: 'Service Completed',
        icon: 'fa-check-circle',
        color: 'emerald',
        progress: 100,
        description: 'Service completed successfully - Thank you for choosing us!'
    }
};


// Initialize dashboard
document.addEventListener('DOMContentLoaded', function() {
    // Get tracking token from URL
    const urlParams = new URLSearchParams(window.location.search);
    trackingToken = urlParams.get('token');
    
    if (!trackingToken) {
        showError('No tracking token provided. Please check your email link.');
        return;
    }
    
    // Load initial data
    loadBookingData();
    
    // Start auto-refresh with shorter interval for real-time updates
    startAutoRefresh();
});

async function loadBookingData() {
    try {
        const response = await fetch(`${API_BASE}guest_dashboard.php?token=${trackingToken}`);
        const result = await response.json();
        
        if (result.success) {
            // Check for status changes
            const newStatus = result.data.status;
            if (lastKnownStatus && lastKnownStatus !== newStatus) {
                showStatusChangeNotification(lastKnownStatus, newStatus);
                // Add visual feedback for status change
                highlightStatusChange();
            }
            
            lastKnownStatus = newStatus;
            currentBookingData = result.data;
            populateDashboard(result.data);
            showDashboard();
        } else {
            showError(result.message || 'Failed to load booking data');
        }
    } catch (error) {
        console.error('Error loading booking data:', error);
        showError('Connection error. Please check your internet connection.');
    }
}

// Updated showStatusChangeNotification function - REPLACE existing function
function showStatusChangeNotification(oldStatus, newStatus) {
    const oldConfig = statusConfig[oldStatus] || {};
    const newConfig = statusConfig[newStatus] || {};
    
    // Special handling for completion
    if (newStatus === 'completed') {
        celebrateCompletion();
        return;
    }
    
    // Create and show notification
    const notification = document.createElement('div');
    notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-6 py-4 rounded-lg shadow-lg z-50 max-w-sm notification-update';
    notification.innerHTML = `
        <div class="flex items-center">
            <i class="fas fa-bell mr-3 text-lg"></i>
            <div>
                <div class="font-semibold">Status Updated!</div>
                <div class="text-sm">Your pet is now: ${newConfig.label}</div>
            </div>
        </div>
    `;
    
    document.body.appendChild(notification);
    
    // Animate notification
    notification.style.transform = 'translateX(100%)';
    setTimeout(() => {
        notification.style.transform = 'translateX(0)';
        notification.style.transition = 'transform 0.3s ease-out';
    }, 100);
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
        notification.style.transform = 'translateX(100%)';
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, 300);
    }, 5000);
    
    // Play notification sound (if supported)
    try {
        const audio = new Audio('data:audio/wav;base64,UklGRnoGAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQoGAACBhYqFbF1fdJivrJBhNjVgodDbq2EcBj+a2/LDciUFLIHO8tiJNwgZaLvt559NEAxQp+PwtmMcBjiR1/LMeSwFJHfH8N2QQAoUXrTp66hVFApGn+T16XspBFiTyO/dg');
        audio.play().catch(() => {});
    } catch (e) {
        // Ignore if audio fails
    }
}

function highlightStatusChange() {
    const statusBadge = document.getElementById('statusBadge');
    if (statusBadge) {
        statusBadge.classList.add('status-highlight');
        setTimeout(() => {
            statusBadge.classList.remove('status-highlight');
        }, 2000);
    }
}

function populateDashboard(data) {
    // Pet Information
    document.getElementById('petName').textContent = data.pet_name;
    document.getElementById('petDetails').textContent = `${data.pet_type} • ${data.pet_breed}${data.age_range ? ` • ${data.age_range}` : ''}${data.size ? ` • ${data.size}` : ''}`;
    document.getElementById('bookingId').textContent = data.booking_id;
    
    // Owner Information
    document.getElementById('ownerName').textContent = data.owner_name;
    document.getElementById('ownerContact').textContent = `${data.owner_phone}${data.owner_email ? ` • ${data.owner_email}` : ''}`;
    
    // Booking Times
    document.getElementById('checkinTime').textContent = formatDateTime(data.check_in_time);
    document.getElementById('estimatedTime').textContent = data.estimated_completion ? formatDateTime(data.estimated_completion) : 'To be determined';
    
    // Status
    updateStatus(data.status);
    
    // Services
    populateServices(data.services);
    
    // Total Amount
    document.getElementById('totalAmount').textContent = `₱${parseFloat(data.total_amount).toFixed(2)}`;
    
    // Special Notes
    if (data.special_notes && data.special_notes.trim()) {
        document.getElementById('specialNotesCard').classList.remove('hidden');
        document.getElementById('specialNotesText').textContent = data.special_notes;
    } else {
        document.getElementById('specialNotesCard').classList.add('hidden');
    }
    
    // Update last refreshed time
    document.getElementById('lastUpdated').textContent = new Date().toLocaleTimeString('en-PH', {
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    });
}

function updateStatus(status) {
    const config = statusConfig[status] || statusConfig['checked-in'];
    
    // Update status badge
    const statusBadge = document.getElementById('statusBadge');
    const statusDot = document.getElementById('statusDot');
    const statusText = document.getElementById('statusText');
    
    statusBadge.className = `inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-${config.color}-100 text-${config.color}-800 border border-${config.color}-200`;
    statusDot.className = `w-2 h-2 rounded-full mr-2 bg-${config.color}-500`;
    statusText.textContent = config.label;
    
    // Add pulse animation for active statuses
    if (['bathing', 'grooming'].includes(status)) {
        statusDot.classList.add('status-pulse');
    } else {
        statusDot.classList.remove('status-pulse');
    }
    
    // Update progress bar
    const progressBar = document.getElementById('progressBar');
    progressBar.style.width = config.progress + '%';
    
    // Update timeline
    updateTimeline(status);
}


// Updated updateTimeline function - replace existing function
function updateTimeline(currentStatus) {
    const timelineSteps = document.getElementById('timelineSteps');
    const steps = ['checked-in', 'bathing', 'grooming', 'ready', 'completed']; // ADDED 'completed'
    
    timelineSteps.innerHTML = steps.map((step, index) => {
        const config = statusConfig[step];
        const isActive = step === currentStatus;
        const isCompleted = steps.indexOf(currentStatus) > index;
        const isPending = steps.indexOf(currentStatus) < index;
        
        let statusClass, iconClass, textClass, timeClass;
        
        if (isCompleted) {
            statusClass = `bg-green-500 border-green-500`;
            iconClass = 'text-white';
            textClass = 'text-green-700 font-semibold';
            timeClass = 'text-green-600';
        } else if (isActive) {
            statusClass = `bg-${config.color}-500 border-${config.color}-500 status-pulse`;
            iconClass = 'text-white';
            textClass = `text-${config.color}-700 font-semibold`;
            timeClass = `text-${config.color}-600`;
        } else {
            statusClass = 'bg-gray-100 border-gray-300';
            iconClass = 'text-gray-400';
            textClass = 'text-gray-500';
            timeClass = 'text-gray-400';
        }
        
        // Get timestamp for this step if available
        let stepTime = '';
        if (currentBookingData && currentBookingData.status_history) {
            const statusUpdate = currentBookingData.status_history.find(s => s.status === step);
            if (statusUpdate) {
                stepTime = formatTime(statusUpdate.created_at);
            }
        }
        
        // Special styling for completed status
        if (step === 'completed' && isActive) {
            statusClass = 'bg-gradient-to-r from-emerald-500 to-green-600 border-emerald-500 completion-glow';
        }
        
        return `
            <div class="relative flex items-start">
                <div class="relative z-10 w-16 h-16 ${statusClass} border-4 rounded-full flex items-center justify-center shadow-lg">
                    <i class="fas ${config.icon} text-xl ${iconClass}"></i>
                    ${step === 'completed' && isActive ? '<div class="absolute -inset-1 bg-gradient-to-r from-emerald-400 to-green-500 rounded-full blur opacity-75 animate-pulse"></div>' : ''}
                </div>
                <div class="ml-6 min-w-0 flex-1">
                    <div class="flex items-center justify-between">
                        <h3 class="text-lg ${textClass}">${config.label}</h3>
                        ${stepTime ? `<span class="text-sm ${timeClass} font-medium">${stepTime}</span>` : ''}
                    </div>
                    <p class="text-sm text-gray-600 mt-1">${config.description}</p>
                    ${isActive && step === 'completed' ? '<div class="mt-2 text-sm font-bold text-emerald-600">🎉 Thank you for choosing 8Paws Pet Boutique!</div>' : ''}
                    ${isActive && step !== 'completed' ? '<div class="mt-2 text-sm font-medium text-blue-600">🔄 Currently in progress...</div>' : ''}
                </div>
            </div>
        `;
    }).join('');
}

// Add completion celebration function - ADD THIS NEW FUNCTION
function celebrateCompletion() {
    // Create celebration overlay
    const celebration = document.createElement('div');
    celebration.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 celebration-overlay';
    celebration.innerHTML = `
        <div class="bg-white rounded-2xl p-8 max-w-md mx-4 text-center transform scale-95 celebration-popup">
            <div class="text-6xl mb-4 animate-bounce">🎉</div>
            <h2 class="text-2xl font-bold text-emerald-600 mb-2">Service Completed!</h2>
            <p class="text-gray-600 mb-4">Thank you for choosing 8Paws Pet Boutique!</p>
            <div class="text-4xl mb-4">✨🐾✨</div>
            <button onclick="closeCelebration()" class="bg-emerald-500 hover:bg-emerald-600 text-white px-6 py-2 rounded-lg font-medium transition-colors">
                Wonderful! 🎊
            </button>
        </div>
    `;
    
    document.body.appendChild(celebration);
    
    // Animate in
    setTimeout(() => {
        celebration.querySelector('.celebration-popup').style.transform = 'scale(1)';
        celebration.querySelector('.celebration-popup').style.transition = 'transform 0.3s ease-out';
    }, 100);
    
    // Auto-remove after 5 seconds if user doesn't close it
    setTimeout(() => {
        if (document.body.contains(celebration)) {
            closeCelebration();
        }
    }, 5000);
}

// Add close celebration function - ADD THIS NEW FUNCTION
window.closeCelebration = function() {
    const celebration = document.querySelector('.celebration-overlay');
    if (celebration) {
        celebration.style.opacity = '0';
        celebration.style.transition = 'opacity 0.3s ease-out';
        setTimeout(() => {
            if (celebration.parentNode) {
                celebration.remove();
            }
        }, 300);
    }
}


function populateServices(services) {
    const servicesList = document.getElementById('servicesList');
    
    if (!services || services.length === 0) {
        servicesList.innerHTML = '<p class="text-gray-500 text-center py-4">No services selected</p>';
        return;
    }
    
    servicesList.innerHTML = services.map(service => `
        <div class="flex justify-between items-center p-4 bg-gray-50 rounded-lg">
            <div>
                <span class="font-medium text-gray-900">${service.name}</span>
                <p class="text-sm text-gray-600">${service.description || 'Professional service'}</p>
            </div>
            <span class="text-lg font-bold text-primary">₱${parseFloat(service.price).toFixed(2)}</span>
        </div>
    `).join('');
}

function startAutoRefresh() {
    // Refresh every 15 seconds for more real-time updates
    refreshInterval = setInterval(async () => {
        try {
            await loadBookingData();
        } catch (error) {
            console.error('Auto-refresh error:', error);
        }
    }, 15000);
}

function stopAutoRefresh() {
    if (refreshInterval) {
        clearInterval(refreshInterval);
        refreshInterval = null;
    }
}

function showDashboard() {
    document.getElementById('loading-screen').classList.add('hidden');
    document.getElementById('error-screen').classList.add('hidden');
    document.getElementById('dashboard-content').classList.remove('hidden');
}

function showError(message) {
    document.getElementById('loading-screen').classList.add('hidden');
    document.getElementById('dashboard-content').classList.add('hidden');
    document.getElementById('error-message').textContent = message;
    document.getElementById('error-screen').classList.remove('hidden');
    
    // Stop auto-refresh if there's an error
    stopAutoRefresh();
}

function redirectToCheckin() {
    window.location.href = 'check_in.html';
}

// Utility functions
function formatDateTime(dateString) {
    if (!dateString) return 'N/A';
    
    const date = new Date(dateString);
    return date.toLocaleString('en-PH', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
    });
}

function formatTime(dateString) {
    if (!dateString) return '';
    
    const date = new Date(dateString);
    return date.toLocaleTimeString('en-PH', {
        hour: '2-digit',
        minute: '2-digit',
        hour12: true
    });
}

// Cleanup on page unload
window.addEventListener('beforeunload', function() {
    stopAutoRefresh();
});

// Handle page visibility change (pause refresh when tab is hidden)
document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
        stopAutoRefresh();
    } else {
        startAutoRefresh();
        // Immediate refresh when tab becomes visible
        loadBookingData();
    }
});