// Guest Dashboard JavaScript
let refreshInterval = null;
let currentBookingData = null;
let trackingToken = null;

// API base URL
const API_BASE = 'http://localhost/8paws/api/';

// Status configuration
const statusConfig = {
    'checked-in': {
        label: 'Checked In',
        icon: 'fa-clipboard-check',
        color: 'blue',
        progress: 25,
        description: 'Your pet has been checked in and is waiting for services'
    },
    'bathing': {
        label: 'Bathing',
        icon: 'fa-bath',
        color: 'indigo',
        progress: 50,
        description: 'Your pet is currently being bathed and pampered'
    },
    'grooming': {
        label: 'Grooming',
        icon: 'fa-scissors',
        color: 'purple',
        progress: 75,
        description: 'Professional grooming services in progress'
    },
    'ready': {
        label: 'Ready for Pickup',
        icon: 'fa-bell',
        color: 'green',
        progress: 100,
        description: 'Your pet is ready! Please come for pickup'
    },
    'completed': {
        label: 'Completed',
        icon: 'fa-check-circle',
        color: 'green',
        progress: 100,
        description: 'Service completed successfully'
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
    
    // Start auto-refresh
    startAutoRefresh();
});

async function loadBookingData() {
    try {
        const response = await fetch(`${API_BASE}guest_dashboard.php?token=${trackingToken}`);
        const result = await response.json();
        
        if (result.success) {
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

function updateTimeline(currentStatus) {
    const timelineSteps = document.getElementById('timelineSteps');
    const steps = ['checked-in', 'bathing', 'grooming', 'ready'];
    
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
        
        return `
            <div class="relative flex items-start">
                <div class="relative z-10 w-16 h-16 ${statusClass} border-4 rounded-full flex items-center justify-center shadow-lg">
                    <i class="fas ${config.icon} text-xl ${iconClass}"></i>
                </div>
                <div class="ml-6 min-w-0 flex-1">
                    <div class="flex items-center justify-between">
                        <h3 class="text-lg ${textClass}">${config.label}</h3>
                        ${stepTime ? `<span class="text-sm ${timeClass} font-medium">${stepTime}</span>` : ''}
                    </div>
                    <p class="text-sm text-gray-600 mt-1">${config.description}</p>
                    ${isActive ? '<div class="mt-2 text-sm font-medium text-blue-600">🔄 Currently in progress...</div>' : ''}
                </div>
            </div>
        `;
    }).join('');
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
    // Refresh every 30 seconds
    refreshInterval = setInterval(async () => {
        try {
            await loadBookingData();
        } catch (error) {
            console.error('Auto-refresh error:', error);
        }
    }, 30000);
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