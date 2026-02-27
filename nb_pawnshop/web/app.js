(() => {
  const app = document.getElementById('app');
  const viewPawn = document.getElementById('viewPawn');
  const viewManage = document.getElementById('viewManage');
  const titleEl = document.getElementById('title');
  const subtitleEl = document.getElementById('subtitle');

  const tabSell = document.getElementById('tabSell');
  const tabBuyback = document.getElementById('tabBuyback');
  const searchPawn = document.getElementById('searchPawn');
  const listPawn = document.getElementById('listPawn');
  const checkoutPawn = document.getElementById('checkoutPawn');
  const listTitle = document.getElementById('listTitle');

  const toastWrap = document.getElementById('toastWrap');

  // Manage
  const navStaff = document.getElementById('navStaff');
  const navBank = document.getElementById('navBank');
  const btnOpenStock = document.getElementById('btnOpenStock');
  const btnToggleClock = document.getElementById('btnToggleClock');
  const mBankBalance = document.getElementById('mBankBalance');
  const mActiveCount = document.getElementById('mActiveCount');
  const mMyStatus = document.getElementById('mMyStatus');
  const mClockHint = document.getElementById('mClockHint');
  const mActiveList = document.getElementById('mActiveList');

  const bankAmount = document.getElementById('bankAmount');
  const btnDeposit = document.getElementById('btnDeposit');
  const btnWithdraw = document.getElementById('btnWithdraw');
  const bankBalanceInline = document.getElementById('bankBalanceInline');

  const custId = document.getElementById('custId');
  const btnLoadCustomer = document.getElementById('btnLoadCustomer');
  const custHint = document.getElementById('custHint');
  const custList = document.getElementById('custList');
  const custCheckout = document.getElementById('custCheckout');

  const staffId = document.getElementById('staffId');
  const staffGrade = document.getElementById('staffGrade');
  const btnHire = document.getElementById('btnHire');
  const btnFire = document.getElementById('btnFire');

  const btnClose = document.getElementById('btnClose');

  const state = {
    mode: null, // 'pawn' | 'manage'
    pawnTab: 'sell', // 'sell' | 'buyback'
    sellables: [],
    stock: [],
    selected: null,
    selectedQty: 1,
    manage: {
      isBoss: false,
      clockedIn: false,
      grade: 0,
      activeStaff: [],
      bankBalance: 0,
      businessBankEnabled: false,
      staffManagementEnabled: false,
    },
    customer: {
      id: null,
      sellables: [],
      selected: null,
      qty: 1,
    },
    title: 'Pawn Shop'
  };

  const money = (n) => {
    try {
      const v = Number(n || 0);
      return '$' + v.toLocaleString(undefined, { maximumFractionDigits: 0 });
    } catch (e) { return '$' + (n || 0); }
  };

  function toast(type, title, desc) {
    const el = document.createElement('div');
    el.className = 'toast ' + (type === 'error' ? 'bad' : 'good');
    el.innerHTML = `<div class="t">${escapeHtml(title || '')}</div><div class="d">${escapeHtml(desc || '')}</div>`;
    toastWrap.appendChild(el);
    setTimeout(() => {
      el.style.opacity = '0';
      el.style.transform = 'translateY(4px)';
      setTimeout(() => el.remove(), 220);
    }, 2200);
  }

  function escapeHtml(s){
    return String(s ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
  }

  async function nui(name, data = {}) {
    const res = await fetch(`https://${GetParentResourceName()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data)
    });
    return res.json().catch(() => ({}));
  }

  function show(mode) {
    state.mode = mode;
    app.classList.remove('hidden');
    if (mode === 'pawn') {
      viewPawn.classList.remove('hidden');
      viewManage.classList.add('hidden');
      subtitleEl.textContent = state.pawnTab === 'sell' ? 'Sell items' : 'Buyback stock';
    } else {
      viewPawn.classList.add('hidden');
      viewManage.classList.remove('hidden');
      subtitleEl.textContent = 'Management';
    }
  }

  function hide() {
    state.mode = null;
    app.classList.add('hidden');
  }

  function setHeader(title, subtitle) {
    titleEl.textContent = title || 'Pawn Shop';
    subtitleEl.textContent = subtitle || '';
  }

  function setPawnTab(tab) {
    state.pawnTab = tab;
    tabSell.classList.toggle('active', tab === 'sell');
    tabBuyback.classList.toggle('active', tab === 'buyback');
    state.selected = null;
    state.selectedQty = 1;
    renderPawn();
  }

  function filteredItems(list) {
    const q = (searchPawn.value || '').trim().toLowerCase();
    if (!q) return list;
    return list.filter(it => (it.label || it.name || '').toLowerCase().includes(q) || (it.name || '').toLowerCase().includes(q));
  }

  function imgForItem(name) {
    // ox_inventory default images
    return `https://cfx-nui-ox_inventory/web/images/${name}.png`;
  }

  function renderList(container, items, selectedName, onSelect) {
    container.innerHTML = '';
    if (!items || items.length === 0) {
      container.innerHTML = `<div class="empty">Nothing here yet.</div>`;
      return;
    }
    items.forEach(it => {
      const el = document.createElement('div');
      el.className = 'item' + (selectedName === it.name ? ' selected' : '');
      el.innerHTML = `
        <div class="icon"><img src="${imgForItem(it.name)}" onerror="this.style.display='none'"/></div>
        <div class="meta">
          <div class="name">${escapeHtml(it.label || it.name)}</div>
          <div class="sub">${escapeHtml(it.name)} • <span class="small">x${it.count}</span></div>
        </div>
        <div class="price">${money(it.price)}</div>
      `;
      el.addEventListener('click', () => onSelect(it));
      container.appendChild(el);
    });
  }

  function renderCheckout(container, selected, qty, maxQty, btnLabel, onConfirm) {
    if (!selected) {
      container.innerHTML = `<div class="empty">Select an item to continue.</div>`;
      return;
    }
    const unit = Number(selected.price || 0);
    const total = unit * Number(qty || 0);
    container.innerHTML = `
      <div class="checkout-card">
        <div class="checkout-head">
          <div class="icon"><img src="${imgForItem(selected.name)}" onerror="this.style.display='none'"/></div>
          <div>
            <div class="checkout-title">${escapeHtml(selected.label || selected.name)}</div>
            <div class="checkout-sub">${escapeHtml(selected.name)} • Available: x${maxQty}</div>
          </div>
        </div>

        <div class="qty">
          <button id="qMinus">−</button>
          <input id="qInput" type="number" min="1" max="${maxQty}" value="${qty}" />
          <button id="qPlus">+</button>
          <div class="spacer"></div>
          <div class="small">Unit: ${money(unit)}</div>
        </div>

        <div class="total">
          <div class="k">Total</div>
          <div class="v">${money(total)}</div>
        </div>

        <div class="actions">
          <button id="btnConfirm" class="btn">${escapeHtml(btnLabel)}</button>
          <button id="btnRefresh" class="btn ghost">Refresh</button>
        </div>
      </div>
    `;

    const qMinus = container.querySelector('#qMinus');
    const qPlus = container.querySelector('#qPlus');
    const qInput = container.querySelector('#qInput');
    const btnConfirm = container.querySelector('#btnConfirm');
    const btnRefresh = container.querySelector('#btnRefresh');

    const clamp = (v) => Math.max(1, Math.min(maxQty, Number(v || 1)));

    qMinus.addEventListener('click', () => {
      const v = clamp((Number(qInput.value) || 1) - 1);
      qInput.value = v;
      onConfirm('qty', v);
    });
    qPlus.addEventListener('click', () => {
      const v = clamp((Number(qInput.value) || 1) + 1);
      qInput.value = v;
      onConfirm('qty', v);
    });
    qInput.addEventListener('input', () => {
      const v = clamp(qInput.value);
      qInput.value = v;
      onConfirm('qty', v);
    });
    btnConfirm.addEventListener('click', () => onConfirm('confirm', clamp(qInput.value)));
    btnRefresh.addEventListener('click', () => onConfirm('refresh', clamp(qInput.value)));
  }

  function renderPawn() {
    setHeader(state.title, state.pawnTab === 'sell' ? 'Sell items' : 'Buyback stock');
    listTitle.textContent = state.pawnTab === 'sell' ? 'Your sellable items' : 'Pawnshop stock (buyback)';
    const items = state.pawnTab === 'sell' ? filteredItems(state.sellables) : filteredItems(state.stock);
    renderList(listPawn, items, state.selected?.name, (it) => {
      state.selected = it;
      state.selectedQty = 1;
      renderPawn();
    });

    const maxQty = state.selected ? (state.selected.count || 1) : 1;
    const label = state.pawnTab === 'sell' ? 'Sell' : 'Buy';
    renderCheckout(checkoutPawn, state.selected, state.selectedQty, maxQty, label, async (type, value) => {
      if (type === 'qty') {
        state.selectedQty = value;
        return;
      }
      if (type === 'refresh') {
        await nui('refreshPawn', {});
        return;
      }
      if (!state.selected) return;
      const qty = value;
      if (state.pawnTab === 'sell') {
        await nui('sell', { item: state.selected.name, qty });
      } else {
        await nui('buyback', { item: state.selected.name, qty });
      }
    });
  }

  function renderActiveStaff() {
    const list = state.manage.activeStaff || [];
    mActiveCount.textContent = String(list.length || 0);
    mActiveList.innerHTML = '';
    if (!list.length) {
      mActiveList.innerHTML = `<div class="empty">No one is clocked in.</div>`;
      return;
    }
    list.forEach(e => {
      const el = document.createElement('div');
      el.className = 'item';
      el.innerHTML = `
        <div class="icon"><div style="width:10px;height:10px;border-radius:999px;background:rgba(120,255,170,0.9)"></div></div>
        <div class="meta">
          <div class="name">${escapeHtml(e.name || 'Employee')}</div>
          <div class="sub">Grade ${escapeHtml(e.grade ?? 0)} • ${escapeHtml(e.since || '')}</div>
        </div>
        <div class="small">On duty</div>
      `;
      mActiveList.appendChild(el);
    });
  }

  function renderManage() {
    setHeader(state.title, 'Management');
    // hide boss-only staff tab if not boss or disabled
    const showStaff = !!(state.manage.isBoss && state.manage.staffManagementEnabled);
    navStaff.classList.toggle('hidden', !showStaff);
    const showBank = !!state.manage.businessBankEnabled;
    navBank.classList.toggle('hidden', !showBank);
    if (!showBank) {
      // if currently on bank, bounce back
      const active = document.querySelector('.nav-btn.active');
      if (active && active.dataset.nav === 'bank') setManageNav('dash');
    }

    mBankBalance.textContent = money(state.manage.bankBalance || 0);
    bankBalanceInline.textContent = money(state.manage.bankBalance || 0);

    mMyStatus.textContent = state.manage.clockedIn ? 'On duty' : 'Off duty';
    mClockHint.textContent = state.manage.clockedIn ? 'You are clocked in.' : 'You are clocked out.';
    renderActiveStaff();
  }

  function setManageNav(nav) {
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.toggle('active', b.dataset.nav === nav));
    const map = {
      dash: document.getElementById('manageDash'),
      bank: document.getElementById('manageBank'),
      counter: document.getElementById('manageCounter'),
      staff: document.getElementById('manageStaff'),
    };
    Object.keys(map).forEach(k => map[k].classList.toggle('hidden', k !== nav));
  }

  function renderCustomerList() {
    const items = state.customer.sellables || [];
    renderList(custList, items, state.customer.selected?.name, (it) => {
      state.customer.selected = it;
      state.customer.qty = 1;
      renderCustomerCheckout();
    });
    renderCustomerCheckout();
  }

  function renderCustomerCheckout() {
    const it = state.customer.selected;
    if (!it) {
      custCheckout.innerHTML = `<div class="empty">Select an item to buy from the customer.</div>`;
      return;
    }
    const maxQty = it.count || 1;
    renderCheckout(custCheckout, it, state.customer.qty, maxQty, 'Buy', async (type, value) => {
      if (type === 'qty') { state.customer.qty = value; return; }
      if (type === 'refresh') {
        await loadCustomer();
        return;
      }
      const qty = value;
      await nui('staffBuyFromCustomer', { customerId: state.customer.id, item: it.name, qty });
    });
  }

  async function loadCustomer() {
    const id = Number(custId.value || 0);
    if (!id) {
      custHint.textContent = 'Enter a valid Server ID.';
      toast('error', 'Counter', 'Enter a valid customer ID.');
      return;
    }
    custHint.textContent = 'Loading…';
    const res = await nui('customerLookup', { customerId: id });
    if (res && res.ok) {
      state.customer.id = id;
      state.customer.sellables = res.items || [];
      state.customer.selected = null;
      state.customer.qty = 1;
      custHint.textContent = `Loaded customer ${id}.`;
      renderCustomerList();
    } else {
      custHint.textContent = res.message || 'Could not load customer.';
      toast('error', 'Counter', res.message || 'Could not load customer.');
    }
  }

  // EVENTS
  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'open') {
      state.title = msg.title || 'Pawn Shop';
      if (msg.mode === 'pawn') {
        state.sellables = msg.sellables || [];
        state.stock = msg.stock || [];
        state.selected = null;
        state.selectedQty = 1;
        searchPawn.value = '';
        setPawnTab('sell');
        show('pawn');
        renderPawn();
      } else if (msg.mode === 'manage') {
        state.manage = Object.assign(state.manage, msg.manage || {});
        state.customer = { id: null, sellables: [], selected: null, qty: 1 };
        custId.value = '';
        custHint.textContent = '';
        bankAmount.value = '';
        show('manage');
        renderManage();
        setManageNav(msg.nav || 'dash');
      }
    } else if (msg.action === 'updatePawn') {
      state.sellables = msg.sellables || state.sellables;
      state.stock = msg.stock || state.stock;
      renderPawn();
      if (msg.toast) toast(msg.toast.type, msg.toast.title, msg.toast.desc);
    } else if (msg.action === 'updateManage') {
      state.manage = Object.assign(state.manage, msg.manage || {});
      renderManage();
      if (msg.toast) toast(msg.toast.type, msg.toast.title, msg.toast.desc);
    } else if (msg.action === 'toast') {
      toast(msg.type || 'info', msg.title || '', msg.desc || '');
    } else if (msg.action === 'hide') {
      hide();
    }
  });

  // UI bindings
  tabSell.addEventListener('click', () => setPawnTab('sell'));
  tabBuyback.addEventListener('click', () => setPawnTab('buyback'));
  searchPawn.addEventListener('input', () => renderPawn());

  document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', () => setManageNav(btn.dataset.nav));
  });

  btnOpenStock.addEventListener('click', async () => {
    await nui('openStock', {});
  });

  btnToggleClock.addEventListener('click', async () => {
    await nui('toggleClock', {});
  });

  btnDeposit.addEventListener('click', async () => {
    const amt = Number(bankAmount.value || 0);
    await nui('bankDeposit', { amount: amt });
  });

  btnWithdraw.addEventListener('click', async () => {
    const amt = Number(bankAmount.value || 0);
    await nui('bankWithdraw', { amount: amt });
  });

  btnLoadCustomer.addEventListener('click', loadCustomer);

  btnHire.addEventListener('click', async () => {
    const id = Number(staffId.value || 0);
    const grade = Number(staffGrade.value || 0);
    await nui('staffSetJob', { targetId: id, grade });
  });

  btnFire.addEventListener('click', async () => {
    const id = Number(staffId.value || 0);
    await nui('staffFire', { targetId: id });
  });

  btnClose.addEventListener('click', async () => {
    await nui('close', {});
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      nui('close', {});
    }
  });

  // Tell Lua we're ready so it can safely SendNUIMessage on first open.
  // This prevents "target disappears but UI doesn't show" on first click.
  // We retry a few times in case Lua hasn't registered the callback yet.
  try {
    let tries = 0;
    const t = setInterval(() => {
      tries++;
      nui('ready', {}).catch(() => {});
      if (tries >= 6) clearInterval(t);
    }, 500);
  } catch (e) {}

})();