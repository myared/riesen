// Care Pathway JavaScript

// Open or create care pathway
function openCarePathway(patientId) {
  // First, try to get existing care pathway or create new one
  fetch(`/patients/${patientId}/care_pathways`, {
    method: 'GET',
    headers: {
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest'
    }
  })
  .then(response => {
    if (response.ok) {
      return response.json();
    } else {
      // No existing pathway, create a new one
      return createCarePathway(patientId);
    }
  })
  .then(data => {
    if (data && data.id) {
      showCarePathway(patientId, data.id);
    }
  })
  .catch(error => console.error('Error opening care pathway:', error));
}

// Create new care pathway
function createCarePathway(patientId) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
  
  return fetch(`/patients/${patientId}/care_pathways`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken,
      'Accept': 'application/json'
    },
    body: JSON.stringify({
      care_pathway: {
        pathway_type: 'triage'  // Default to triage for new pathways
      }
    })
  })
  .then(response => response.json());
}

// Show care pathway modal
function showCarePathway(patientId, pathwayId) {
  fetch(`/patients/${patientId}/care_pathways/${pathwayId}`, {
    headers: {
      'Accept': 'text/html',
      'X-Requested-With': 'XMLHttpRequest'
    }
  })
  .then(response => response.text())
  .then(html => {
    const modalContainer = document.getElementById('care-pathway-modal-container');
    if (modalContainer) {
      modalContainer.innerHTML = html;
      modalContainer.style.display = 'block';
      initializeCarePathwayEvents();
    }
  })
  .catch(error => console.error('Error loading care pathway:', error));
}

// Close care pathway modal
function closeCarePathwayModal() {
  const modalContainer = document.getElementById('care-pathway-modal-container');
  if (modalContainer) {
    modalContainer.style.display = 'none';
    modalContainer.innerHTML = '';
  }
}

// Complete triage step
function completeTriageStep(patientId, pathwayId, stepId) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
  
  fetch(`/patients/${patientId}/care_pathways/${pathwayId}/complete_step/${stepId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken,
      'Accept': 'application/json'
    }
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      // Reload the care pathway modal to show updated state
      showCarePathway(patientId);
    } else {
      alert('Failed to complete step');
    }
  })
  .catch(error => console.error('Error completing step:', error));
}

// Advance order status
function advanceOrderStatus(patientId, pathwayId, orderId) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
  
  fetch(`/patients/${patientId}/care_pathways/${pathwayId}/update_order_status/${orderId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken,
      'Accept': 'application/json'
    }
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      // Update the order status display
      updateOrderDisplay(orderId, data.status);
      updateProgressPercentage(data.progress);
    } else {
      alert('Failed to update order status');
    }
  })
  .catch(error => console.error('Error updating order status:', error));
}

// Complete procedure
function completeProcedure(patientId, pathwayId, procedureId) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
  
  fetch(`/patients/${patientId}/care_pathways/${pathwayId}/complete_procedure/${procedureId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken,
      'Accept': 'application/json'
    }
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      // Update the procedure display
      updateProcedureDisplay(procedureId, true);
      updateProgressPercentage(data.progress);
    } else {
      alert('Failed to complete procedure');
    }
  })
  .catch(error => console.error('Error completing procedure:', error));
}

// Achieve clinical endpoint
function achieveEndpoint(patientId, pathwayId, endpointId) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
  
  fetch(`/patients/${patientId}/care_pathways/${pathwayId}/achieve_endpoint/${endpointId}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken,
      'Accept': 'application/json'
    }
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      // Update the endpoint display
      updateEndpointDisplay(endpointId, true);
      updateProgressPercentage(data.progress);
    } else {
      alert('Failed to achieve endpoint');
    }
  })
  .catch(error => console.error('Error achieving endpoint:', error));
}

// Show add order modal
function showAddOrderModal(patientId, pathwayId) {
  // Create and show modal for adding orders
  const modal = createAddOrderModal(patientId, pathwayId);
  document.body.appendChild(modal);
}

// Show add procedure modal
function showAddProcedureModal(patientId, pathwayId) {
  // Create and show modal for adding procedures
  const modal = createAddProcedureModal(patientId, pathwayId);
  document.body.appendChild(modal);
}

// Show add endpoint modal
function showAddEndpointModal(patientId, pathwayId) {
  // Create and show modal for adding clinical endpoints
  const modal = createAddEndpointModal(patientId, pathwayId);
  document.body.appendChild(modal);
}

// Helper function to create add order modal
function createAddOrderModal(patientId, pathwayId) {
  const modal = document.createElement('div');
  modal.className = 'modal-overlay';
  modal.innerHTML = `
    <div class="modal-content add-order-modal">
      <h3>Add Order</h3>
      <div class="order-type-tabs">
        <button class="tab-btn active" data-type="lab">Labs</button>
        <button class="tab-btn" data-type="medication">Meds</button>
        <button class="tab-btn" data-type="imaging">Imaging</button>
      </div>
      <div class="order-options" id="order-options">
        <!-- Options will be populated based on selected type -->
      </div>
      <div class="modal-actions">
        <button onclick="submitOrder(${patientId}, ${pathwayId})" class="btn btn-primary">Add Order</button>
        <button onclick="closeModal(this)" class="btn btn-secondary">Cancel</button>
      </div>
    </div>
  `;
  
  // Add event listeners for tabs
  modal.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', function() {
      modal.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      this.classList.add('active');
      loadOrderOptions(this.dataset.type);
    });
  });
  
  // Load initial options
  loadOrderOptions('lab');
  
  return modal;
}

// Helper function to create add procedure modal
function createAddProcedureModal(patientId, pathwayId) {
  const modal = document.createElement('div');
  modal.className = 'modal-overlay';
  modal.innerHTML = `
    <div class="modal-content add-procedure-modal">
      <h3>Add Procedure</h3>
      <select id="procedure-select" class="form-control">
        <option value="">Select a procedure...</option>
        ${getProcedureOptions()}
      </select>
      <textarea id="procedure-notes" class="form-control" placeholder="Additional notes (optional)"></textarea>
      <div class="modal-actions">
        <button onclick="submitProcedure(${patientId}, ${pathwayId})" class="btn btn-primary">Add Procedure</button>
        <button onclick="closeModal(this)" class="btn btn-secondary">Cancel</button>
      </div>
    </div>
  `;
  
  return modal;
}

// Helper function to create add endpoint modal
function createAddEndpointModal(patientId, pathwayId) {
  const modal = document.createElement('div');
  modal.className = 'modal-overlay';
  modal.innerHTML = `
    <div class="modal-content add-endpoint-modal">
      <h3>Add Clinical Endpoint</h3>
      <select id="endpoint-select" class="form-control">
        <option value="">Select a clinical goal...</option>
        ${getEndpointOptions()}
      </select>
      <textarea id="endpoint-description" class="form-control" placeholder="Description (required)"></textarea>
      <div class="modal-actions">
        <button onclick="submitEndpoint(${patientId}, ${pathwayId})" class="btn btn-primary">Add Goal</button>
        <button onclick="closeModal(this)" class="btn btn-secondary">Cancel</button>
      </div>
    </div>
  `;
  
  return modal;
}

// Load order options based on type
function loadOrderOptions(type) {
  const container = document.getElementById('order-options');
  let options = [];
  
  switch(type) {
    case 'lab':
      options = [
        'CBC with Differential', 'Basic Metabolic Panel', 'Comprehensive Metabolic Panel',
        'Liver Function Tests', 'Lipid Panel', 'PT/INR', 'PTT', 'Troponin',
        'BNP', 'D-Dimer', 'Urinalysis', 'Urine Culture', 'Blood Culture',
        'Lactate', 'Arterial Blood Gas', 'COVID-19 PCR', 'Rapid Strep', 'Influenza A/B'
      ];
      break;
    case 'medication':
      options = [
        'Acetaminophen 650mg PO', 'Ibuprofen 400mg PO', 'Morphine 2mg IV',
        'Zofran 4mg IV', 'Normal Saline 1L IV', 'Ceftriaxone 1g IV',
        'Azithromycin 500mg PO', 'Prednisone 40mg PO', 'Albuterol Nebulizer',
        'Epinephrine 0.3mg IM', 'Nitroglycerin 0.4mg SL', 'Aspirin 325mg PO',
        'Heparin 5000 units SC', 'Lorazepam 1mg IV'
      ];
      break;
    case 'imaging':
      options = [
        'Chest X-Ray', 'Abdominal X-Ray', 'CT Head without Contrast',
        'CT Chest with PE Protocol', 'CT Abdomen/Pelvis with Contrast',
        'MRI Brain', 'Ultrasound Abdomen', 'Ultrasound Lower Extremity DVT',
        'Echocardiogram', 'EKG'
      ];
      break;
  }
  
  container.innerHTML = `
    <select id="order-select" class="form-control" multiple size="10">
      ${options.map(opt => `<option value="${opt}">${opt}</option>`).join('')}
    </select>
  `;
}

// Get procedure options
function getProcedureOptions() {
  const procedures = [
    'IV Access Placement', 'Foley Catheter Insertion', 'Nasogastric Tube Placement',
    'Central Line Placement', 'Arterial Line Placement', 'Lumbar Puncture',
    'Paracentesis', 'Thoracentesis', 'Wound Closure/Suturing',
    'Wound Irrigation and Debridement', 'Splint Application', 'Cast Application',
    'Joint Reduction', 'Incision and Drainage', 'Foreign Body Removal',
    'Cardioversion', 'Intubation', 'Chest Tube Placement',
    'Procedural Sedation', 'Point of Care Ultrasound'
  ];
  
  return procedures.map(p => `<option value="${p}">${p}</option>`).join('');
}

// Get endpoint options
function getEndpointOptions() {
  const endpoints = [
    'Pain Control (Score < 4)', 'Hemodynamic Stability', 'Normal Vital Signs',
    'Afebrile (Temp < 38°C)', 'Adequate Oxygenation (SpO2 > 94%)',
    'Symptom Resolution', 'Bleeding Controlled', 'Nausea/Vomiting Resolved',
    'Able to Tolerate PO', 'Ambulating Independently', 'Mental Status at Baseline',
    'Infection Source Identified', 'Antibiotics Started', 'Diagnostic Workup Complete',
    'Disposition Plan Established', 'Patient Education Completed',
    'Follow-up Arranged', 'Social Work Evaluation Complete',
    'Safe for Discharge', 'Family Updated'
  ];
  
  return endpoints.map(e => `<option value="${e}">${e}</option>`).join('');
}

// Close modal
function closeModal(element) {
  const modal = element.closest('.modal-overlay');
  if (modal) {
    modal.remove();
  }
}

// Submit functions for modals
function submitOrder(patientId, pathwayId) {
  const select = document.getElementById('order-select');
  const selectedOptions = Array.from(select.selectedOptions);
  const activeTab = document.querySelector('.tab-btn.active');
  const orderType = activeTab.dataset.type;
  
  selectedOptions.forEach(option => {
    addOrder(patientId, pathwayId, option.value, orderType);
  });
  
  closeModal(select);
  // Reload care pathway
  setTimeout(() => showCarePathway(patientId), 500);
}

function submitProcedure(patientId, pathwayId) {
  const select = document.getElementById('procedure-select');
  const notes = document.getElementById('procedure-notes').value;
  
  if (select.value) {
    addProcedure(patientId, pathwayId, select.value, notes);
    closeModal(select);
    // Reload care pathway
    setTimeout(() => showCarePathway(patientId), 500);
  }
}

function submitEndpoint(patientId, pathwayId) {
  const select = document.getElementById('endpoint-select');
  const description = document.getElementById('endpoint-description').value;
  
  if (select.value && description) {
    addClinicalEndpoint(patientId, pathwayId, select.value, description);
    closeModal(select);
    // Reload care pathway
    setTimeout(() => showCarePathway(patientId), 500);
  }
}

// API calls for adding items
function addOrder(patientId, pathwayId, name, orderType) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
  
  fetch(`/patients/${patientId}/care_pathways/${pathwayId}/add_order`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken
    },
    body: JSON.stringify({
      order: { name: name, order_type: orderType }
    })
  });
}

function addProcedure(patientId, pathwayId, name, notes) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
  
  fetch(`/patients/${patientId}/care_pathways/${pathwayId}/add_procedure`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken
    },
    body: JSON.stringify({
      procedure: { name: name, notes: notes }
    })
  });
}

function addClinicalEndpoint(patientId, pathwayId, name, description) {
  const csrfToken = document.querySelector('meta[name="csrf-token"]').content;
  
  fetch(`/patients/${patientId}/care_pathways/${pathwayId}/add_clinical_endpoint`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': csrfToken
    },
    body: JSON.stringify({
      endpoint: { name: name, description: description }
    })
  });
}

// Update display functions
function updateOrderDisplay(orderId, status) {
  const orderElement = document.querySelector(`[data-order-id="${orderId}"]`);
  if (orderElement) {
    // Update status display
    const statusSteps = orderElement.querySelectorAll('.status-step');
    // Update based on new status
  }
}

function updateProcedureDisplay(procedureId, completed) {
  const procedureElement = document.querySelector(`[data-procedure-id="${procedureId}"]`);
  if (procedureElement) {
    if (completed) {
      procedureElement.classList.add('procedure-completed');
      const button = procedureElement.querySelector('.btn-complete');
      if (button) {
        button.style.display = 'none';
      }
    }
  }
}

function updateEndpointDisplay(endpointId, achieved) {
  const endpointElement = document.querySelector(`[data-endpoint-id="${endpointId}"]`);
  if (endpointElement) {
    if (achieved) {
      endpointElement.classList.add('endpoint-achieved');
      const button = endpointElement.querySelector('.btn-achieve');
      if (button) {
        button.style.display = 'none';
      }
    }
  }
}

function updateProgressPercentage(percentage) {
  const progressElement = document.querySelector('.progress-percentage');
  if (progressElement) {
    progressElement.textContent = `${percentage}%`;
  }
}

// Initialize care pathway events
function initializeCarePathwayEvents() {
  // Tab switching for ER pathway
  const tabButtons = document.querySelectorAll('.er-pathway-tabs .tab-button');
  tabButtons.forEach(button => {
    button.addEventListener('click', function() {
      const targetTab = this.dataset.tab;
      
      // Remove active class from all tabs and contents
      tabButtons.forEach(btn => btn.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
      });
      
      // Add active class to clicked tab and corresponding content
      this.classList.add('active');
      document.getElementById(targetTab)?.classList.add('active');
    });
  });
}

// Export functions for global use
window.openCarePathway = openCarePathway;
window.showCarePathway = showCarePathway;
window.closeCarePathwayModal = closeCarePathwayModal;
window.completeTriageStep = completeTriageStep;
window.advanceOrderStatus = advanceOrderStatus;
window.completeProcedure = completeProcedure;
window.achieveEndpoint = achieveEndpoint;
window.showAddOrderModal = showAddOrderModal;
window.showAddProcedureModal = showAddProcedureModal;
window.showAddEndpointModal = showAddEndpointModal;
window.closeModal = closeModal;
window.submitOrder = submitOrder;
window.submitProcedure = submitProcedure;
window.submitEndpoint = submitEndpoint;