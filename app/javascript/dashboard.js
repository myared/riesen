document.addEventListener('DOMContentLoaded', function() {
  // Add Patient button
  const addPatientBtn = document.querySelector('[data-action="add-patient"]');
  if (addPatientBtn) {
    addPatientBtn.addEventListener('click', function() {
      fetch('/simulation/add_patient', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'text/html'
        }
      }).then(() => {
        window.location.reload();
      });
    });
  }
  
  // Advance Time button
  const advanceTimeBtn = document.querySelector('[data-action="advance-time"]');
  if (advanceTimeBtn) {
    advanceTimeBtn.addEventListener('click', function() {
      fetch('/simulation/advance_time', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'text/html'
        },
        body: JSON.stringify({ minutes: 10 })
      }).then(() => {
        window.location.reload();
      });
    });
  }
  
  // Patient row click handler
  const patientRows = document.querySelectorAll('.patient-row');
  patientRows.forEach(row => {
    row.addEventListener('click', function(e) {
      if (e.target.closest('button')) return; // Skip if clicking on a button
      
      const patientId = this.dataset.patientId;
      if (patientId) {
        window.location.href = `/patients/${patientId}`;
      }
    });
  });
});