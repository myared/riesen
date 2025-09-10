// Add immediate console log to verify file is loaded
console.log('🚀 dashboard.js loaded at', new Date().toISOString());

// Function to initialize dashboard interactions
function initializeDashboard() {
  console.log('📌 initializeDashboard() called');
  
  // Add Patient button
  const addPatientBtn = document.querySelector('[data-action="add-patient"]');
  console.log('🔍 Looking for Add Patient button:', addPatientBtn);
  
  if (addPatientBtn) {
    console.log('✅ Add Patient button found');
    if (!addPatientBtn.dataset.listenerAdded) {
      addPatientBtn.dataset.listenerAdded = 'true';
      addPatientBtn.addEventListener('click', function(e) {
        console.log('🔴 Add Patient button clicked!');
        console.log('Event:', e);
        e.preventDefault();
        
        const csrfToken = document.querySelector('[name="csrf-token"]')?.content;
        console.log('CSRF Token:', csrfToken ? 'Found' : 'NOT FOUND');
        
        fetch('/simulation/add_patient', {
          method: 'POST',
          headers: {
            'X-CSRF-Token': csrfToken || '',
            'Accept': 'text/html'
          }
        }).then(response => {
          console.log('✅ Response received:', response.status);
          window.location.reload();
        }).catch(error => {
          console.error('❌ Error adding patient:', error);
        });
      });
      console.log('✅ Add Patient button listener attached successfully');
    } else {
      console.log('⚠️ Add Patient button already has listener');
    }
  } else {
    console.log('❌ Add Patient button NOT found');
  }
  
  // Advance Time button
  const advanceTimeBtn = document.querySelector('[data-action="advance-time"]');
  if (advanceTimeBtn && !advanceTimeBtn.dataset.listenerAdded) {
    advanceTimeBtn.dataset.listenerAdded = 'true';
    advanceTimeBtn.addEventListener('click', function() {
      console.log('Advance Time button clicked');
      fetch('/simulation/advance_time', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'text/html'
        },
        body: JSON.stringify({ minutes: 10 })
      }).then(response => {
        console.log('Response received:', response.status);
        window.location.reload();
      }).catch(error => {
        console.error('Error advancing time:', error);
      });
    });
    console.log('Advance Time button listener attached');
  }
  
  // Patient row click handler
  const patientRows = document.querySelectorAll('.patient-row');
  patientRows.forEach(row => {
    if (!row.dataset.listenerAdded) {
      row.dataset.listenerAdded = 'true';
      row.addEventListener('click', function(e) {
        if (e.target.closest('button')) return; // Skip if clicking on a button
        
        const patientId = this.dataset.patientId;
        if (patientId) {
          window.location.href = `/patients/${patientId}`;
        }
      });
    }
  });
}

// Initialize on DOMContentLoaded
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOMContentLoaded fired');
  initializeDashboard();
});

// Initialize on Turbo load (for navigation)
document.addEventListener('turbo:load', function() {
  console.log('turbo:load fired');
  initializeDashboard();
});

// Also initialize on Turbo frame loads
document.addEventListener('turbo:frame-load', function() {
  console.log('turbo:frame-load fired');
  initializeDashboard();
});