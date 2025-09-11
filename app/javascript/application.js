// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

function showAddOrderModal(patientId, pathwayId) {
  const modal = document.getElementById('add-order-modal');
  if (modal) {
    modal.style.display = 'flex';
    const form = document.getElementById('add-order-form');
    form.action = `/patients/${patientId}/care_pathways/${pathwayId}/add_order`;
  }
}

function advanceOrderStatus(patientId, pathwayId, orderId) {
  const url = `/patients/${patientId}/care_pathways/${pathwayId}/update_order_status/${orderId}`;
  const token = document.querySelector('meta[name="csrf-token"]').content;

  fetch(url, {
    method: 'POST',
    headers: {
      'X-CSRF-Token': token,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      Turbo.visit(window.location, { action: "replace" });
    } else {
      alert('Failed to advance order status.');
    }
  })
  .catch(error => console.error('Error:', error));
}

function showAddProcedureModal(patientId, pathwayId) {
  const modal = document.getElementById('add-procedure-modal');
  if (modal) {
    modal.style.display = 'flex';
    const form = document.getElementById('add-procedure-form');
    form.action = `/patients/${patientId}/care_pathways/${pathwayId}/add_procedure`;
  }
}

function completeProcedure(patientId, pathwayId, procedureId) {
  const url = `/patients/${patientId}/care_pathways/${pathwayId}/complete_procedure/${procedureId}`;
  const token = document.querySelector('meta[name="csrf-token"]').content;

  fetch(url, {
    method: 'POST',
    headers: {
      'X-CSRF-Token': token,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      Turbo.visit(window.location, { action: "replace" });
    } else {
      alert('Failed to complete procedure.');
    }
  })
  .catch(error => console.error('Error:', error));
}

function showAddEndpointModal(patientId, pathwayId) {
  const modal = document.getElementById('add-endpoint-modal');
  if (modal) {
    modal.style.display = 'flex';
    const form = document.getElementById('add-endpoint-form');
    form.action = `/patients/${patientId}/care_pathways/${pathwayId}/add_clinical_endpoint`;
  }
}

function achieveEndpoint(patientId, pathwayId, endpointId) {
  const url = `/patients/${patientId}/care_pathways/${pathwayId}/achieve_endpoint/${endpointId}`;
  const token = document.querySelector('meta[name="csrf-token"]').content;

  fetch(url, {
    method: 'POST',
    headers: {
      'X-CSRF-Token': token,
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      Turbo.visit(window.location, { action: "replace" });
    } else {
      alert('Failed to achieve endpoint.');
    }
  })
  .catch(error => console.error('Error:', error));
}


document.addEventListener('turbo:load', () => {
  // Orders Modal
  const addOrderModal = document.getElementById('add-order-modal');
  if (addOrderModal) {
    document.getElementById('cancel-add-order').addEventListener('click', () => {
      addOrderModal.style.display = 'none';
    });
    
    const closeOrderBtn = document.getElementById('close-add-order');
    if (closeOrderBtn) {
      closeOrderBtn.addEventListener('click', () => {
        addOrderModal.style.display = 'none';
      });
    }
    
    // Click outside to close
    addOrderModal.addEventListener('click', (e) => {
      if (e.target === addOrderModal) {
        addOrderModal.style.display = 'none';
      }
    });

    const orderTypeTabs = addOrderModal.querySelectorAll('.tab-btn');
    const orderTypeInput = document.getElementById('order_type_input');
    const labOrders = document.getElementById('lab-orders');
    const imagingOrders = document.getElementById('imaging-orders');
    const medicationOrders = document.getElementById('medication-orders');

    orderTypeTabs.forEach(tab => {
      tab.addEventListener('click', () => {
        orderTypeTabs.forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        const orderType = tab.dataset.orderType;
        orderTypeInput.value = orderType;

        labOrders.style.display = 'none';
        imagingOrders.style.display = 'none';
        medicationOrders.style.display = 'none';

        if (orderType === 'lab') {
          labOrders.style.display = 'block';
        } else if (orderType === 'imaging') {
          imagingOrders.style.display = 'block';
        } else if (orderType === 'medication') {
          medicationOrders.style.display = 'block';
        }
      });
    });
  }

  // Procedures Modal
  const addProcedureModal = document.getElementById('add-procedure-modal');
  if (addProcedureModal) {
    document.getElementById('cancel-add-procedure').addEventListener('click', () => {
      addProcedureModal.style.display = 'none';
    });
    
    const closeProcedureBtn = document.getElementById('close-add-procedure');
    if (closeProcedureBtn) {
      closeProcedureBtn.addEventListener('click', () => {
        addProcedureModal.style.display = 'none';
      });
    }
    
    // Click outside to close
    addProcedureModal.addEventListener('click', (e) => {
      if (e.target === addProcedureModal) {
        addProcedureModal.style.display = 'none';
      }
    });
  }

  // Endpoints Modal
  const addEndpointModal = document.getElementById('add-endpoint-modal');
  if (addEndpointModal) {
    document.getElementById('cancel-add-endpoint').addEventListener('click', () => {
      addEndpointModal.style.display = 'none';
    });
    
    const closeEndpointBtn = document.getElementById('close-add-endpoint');
    if (closeEndpointBtn) {
      closeEndpointBtn.addEventListener('click', () => {
        addEndpointModal.style.display = 'none';
      });
    }
    
    // Click outside to close
    addEndpointModal.addEventListener('click', (e) => {
      if (e.target === addEndpointModal) {
        addEndpointModal.style.display = 'none';
      }
    });
  }
    
  // Tabs in modal
  const tabButtons = document.querySelectorAll('.tab-button');
  const tabContents = document.querySelectorAll('.tab-content');

  tabButtons.forEach(button => {
    button.addEventListener('click', () => {
      tabButtons.forEach(btn => btn.classList.remove('active'));
      button.classList.add('active');

      const tabId = button.dataset.tab;
      tabContents.forEach(content => {
        if (content.id === tabId) {
          content.classList.add('active');
        } else {
          content.classList.remove('active');
        }
      });
    });
  });
});

window.showAddOrderModal = showAddOrderModal;
window.advanceOrderStatus = advanceOrderStatus;
window.showAddProcedureModal = showAddProcedureModal;
window.completeProcedure = completeProcedure;
window.showAddEndpointModal = showAddEndpointModal;
window.achieveEndpoint = achieveEndpoint;

