const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
for (const match of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(match[1]);

function fixture() {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, {
      value: '', style: {}, classList: { add() {}, remove() {}, toggle() {} },
      open: false, showModal() { this.open = true; },
      textContent: '', innerHTML: '', disabled: false
    });
    return elements.get(id);
  };
  const opened = [], requests = [], alerts = [];
  const context = vm.createContext({
    document: { getElementById: element, querySelectorAll: () => [] },
    window: { open(url) {
      const tab = { url, opener: {}, location: { replace(url) { tab.url = url; } }, close() { tab.closed = true; } };
      opened.push(tab); return tab;
    } },
    alert: msg => alerts.push(msg), confirm: () => true,
    console, Date, encodeURIComponent,
    PLANES_SUB: { plan5: { nombre: 'Paquete 5 clases', clases: 5, precio: 1650, meses: 1 } },
    METODO_LINK_BAC: 'link_bac', METODO_TRANSFER: 'transferencia',
    IDS_METODO_COMPRA: ['link_bac', 'transferencia'],
    METODOS_COMPRA: [{ id: 'link_bac', txt: 'Link de pago BAC' }, { id: 'transferencia', txt: 'Transferencia bancaria' }],
    LINK_CON_CANTIDAD: [], WA: '50500000000', compraActual: null,
    linkDePago: plan => plan === 'plan5' ? 'https://checkout.baccredomatic.com/plan5' : '',
    fmtC: n => 'C$' + n, emailValido: v => /.+@.+\..+/.test(v),
    escHtml: v => String(v), escArg: v => String(v),
    guardarPagoEnCurso: d => requests.push({ storage: d }),
    notificarSolicitudCorreo: d => requests.push({ notification: d }),
    SB_ON: true, staffActual: null,
    sbRpc: async (name, data) => { requests.push({ name, data }); return true; },
    sbFetch: async () => { throw Error('Unexpected direct table write'); },
    SLOTS: {}, slotKey: () => 'slot', COL_DESCUENTO: true,
    guardarRespaldoLocal() {}, esColumnaFaltante: () => false
  });
  for (const name of ['mensajeTransferencia', 'transferWA', 'payLink', 'abrirCompra', 'enviarCompra', 'autoRegisterSub', 'saveSlot', 'proceedToConfirm']) {
    const match = html.match(new RegExp('(?:async )?function ' + name + '\\([^]*?\\n}'));
    assert(match, name);
    vm.runInContext(match[0], context);
  }
  return { context, element, opened, requests, alerts };
}

async function purchase(method) {
  const f = fixture();
  f.context[method === 'link_bac' ? 'payLink' : 'transferWA']('plan5');
  assert.strictEqual(f.opened.length, 0);
  assert.match(f.element('compraResumen').textContent, /Paquete 5 clases.*1650.*5 clase/);
  f.element('compraNombre').value = 'Ana Perez';
  f.element('compraEmail').value = 'ana@example.com';
  f.element('compraTel').value = '88888888';
  await f.context.enviarCompra({ preventDefault() {} });
  assert.strictEqual(f.requests[0].name, 'solicitar_compra_publica');
  assert.strictEqual(f.requests[0].data.p_metodo, method);
  assert.strictEqual(f.requests[0].data.p_plan, 'plan5');
  assert.strictEqual(f.requests.some(r => r.name === 'reservar_con_plan'), false);
  assert.strictEqual(f.opened.length, 1);
  assert.strictEqual(f.opened[0].opener, null);
  if (method === 'link_bac') {
    assert.strictEqual(f.opened[0].url, 'https://checkout.baccredomatic.com/plan5');
    assert(f.requests.some(r => r.storage && r.storage.plan === 'plan5'));
    assert.match(f.element('compraResultado').innerHTML, /Ya pagué/);
  } else {
    assert.match(f.opened[0].url, /^https:\/\/wa.me\//);
    const message = new URL(f.opened[0].url).searchParams.get('text');
    assert.match(message, /Soy Ana Perez.*por transferencia.*Paquete 5 clases.*1650/);
    assert(message.length < 220);
    assert(!/COMPROBANTE|Lugar|Instructora/.test(message));
    assert(!f.requests.some(r => r.storage));
  }
}

(async () => {
  await purchase('link_bac');
  await purchase('transferencia');
  {
    const f = fixture();
    f.context.sbRpc = async () => { throw Error('Compra rechazada'); };
    f.context.payLink('plan5');
    for (const [id, value] of [['compraNombre', 'Ana'], ['compraEmail', 'ana@example.com'], ['compraTel', '88888888']]) f.element(id).value = value;
    await f.context.enviarCompra({ preventDefault() {} });
    assert(f.opened[0].closed);
    assert.match(f.element('compraError').textContent, /Compra rechazada/);
    assert.strictEqual(f.element('compraEnviar').disabled, false);
    assert(!f.requests.length);
  }
  {
    const f = fixture();
    f.context.booking = { clase: 'pilates', dateStr: '2026-10-20', hora: '10:00', instructor: 'Coach' };
    Object.assign(f.context, {
      INFO: { pilates: { nombre: 'Pilates' } }, DIAS_ES: [], MESES_ES: [],
      clasesEnReserva: () => 1, pagoMetodo: 'sub', selectedSubPlan: 'plan5', subPagoComo: 'link_bac',
      findSuscriptora: async () => null, subVencida: () => false, esIlimitada: () => false
    });
    await f.context.proceedToConfirm();
    assert(f.element('compraDialog').open);
    assert.strictEqual(f.opened.length, 0);
    assert.strictEqual(f.requests.length, 0);
    assert.strictEqual(Object.keys(f.context.SLOTS).length, 0);
  }
  {
    const f = fixture();
    const active = { id: 'SUB-ANA', plan: 'plan5', activa: true, clasesRestantes: 5 };
    Object.assign(f.context, {
      booking: { clase: 'pilates', dateStr: '2026-10-20', hora: '10:00', instructor: 'Coach', lugar: 1 },
      INFO: { pilates: { nombre: 'Pilates', emoji: 'P' } }, DIAS_ES: [], MESES_ES: [],
      clasesEnReserva: () => 1, pagoMetodo: 'sub', selectedSubPlan: null,
      findSuscriptora: async () => active, subVencida: () => false, esIlimitada: () => false,
      sincronizarCuposPublico: async () => {}, getClientes: () => [], cuposDe: () => 10,
      inscripcionCerrada: () => false, yaTieneReserva: async () => false,
      getOcupados: () => 0, hora12: h => h, mFlow: [1, 2, 3], mGoStep() {}, renderCards() {},
      cobrarClase: () => { throw Error('El saldo debe cobrarse en la transaccion del servidor'); }
    });
    await f.context.proceedToConfirm();
    assert.strictEqual(f.requests[0].name, 'reservar_con_plan');
    assert.strictEqual(f.requests.length, 1);
    assert.strictEqual(f.opened.length, 0);
    assert.strictEqual(f.element('waLink').style.display, 'none');
    assert.strictEqual(f.element('confirmTitulo').textContent, '¡Reservada! ✓');
  }
  {
    const f = fixture();
    await f.context.saveSlot('pilates', '2026-10-20', '10:00', { nombre: 'Ana', claseDescontada: true });
    assert.strictEqual(f.requests[0].name, 'reservar_con_plan');
    assert.strictEqual(f.context.SLOTS.slot.length, 1);
  }
  {
    const f = fixture();
    f.context.sbRpc = async () => { throw Error('Sin plan activo'); };
    await assert.rejects(() => f.context.saveSlot('pilates', '2026-10-20', '10:00', { nombre: 'Ana' }), /Sin plan activo/);
    assert.strictEqual(Object.keys(f.context.SLOTS).length, 0);
  }
  assert(!/<option value="efectivo"|id="msbCash"|selectMetodo\('cash'\)/.test(html));
  console.log('OK: sintaxis, tarjeta, transferencia, compra fallida, compra sin reserva, reserva mediante RPC y rechazo sin cupo.');
})().catch(error => { console.error(error); process.exitCode = 1; });
