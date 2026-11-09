const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

function fixture(rows, missingColumn = '') {
  const requests = [];
  const context = vm.createContext({
    SB_ON: true, SLOTS: {}, COL_CANCELADA: true,
    SUBS: [], SUBS_IDS: [], SUBS_SNAP: '', snapSubs: x => x.length,
    ASIST: new Map(), COL_ASISTIO: true,
    rowToSub: x => x, guardarRespaldoLocal() {},
    esColumnaFaltante: e => /asistio/.test(e.body || ''),
    sbFetch: async url => {
      requests.push(url);
      if (missingColumn && url.includes(missingColumn)) {
        const error = new Error('missing column');
        error.body = missingColumn;
        throw error;
      }
      const [table, query] = url.split('?');
      const params = new URLSearchParams(query);
      const offset = Number(params.get('offset'));
      const limit = Math.min(Number(params.get('limit')), 1000);
      return rows[table].slice(offset, offset + limit);
    }
  });
  for (const name of ['sbFetchTodo', 'sincronizarReservas', 'sincronizarSubs',
                       'asistKeyDe', 'sincronizarAsistencias']) {
    const match = html.match(new RegExp('(?:async )?function ' + name + '\\([^]*?\\n}'));
    assert.ok(match, name);
    vm.runInContext(match[0], context);
  }
  return { context, requests };
}

const reservations = Array.from({ length: 2300 }, (_, id) => ({
  id: id + 1, ts: id + 1,
  slot_key: id >= 2297 ? 'presenza_essenza_2026-11-09_1930' : `old_${id}`,
  nombre: `Alumna ${id}`, email: `a${id}@example.com`, clase: 'essenza',
  fecha: id >= 2297 ? '2026-11-09' : '2026-08-01', hora: '19:30'
}));

(async () => {
  const many = fixture({ reservas: reservations, suscriptoras: [], asistencias: [] });
  await many.context.sincronizarReservas();
  assert.equal(many.context.SLOTS['presenza_essenza_2026-11-09_1930'].length, 3);
  assert.equal(many.requests.length, 3);
  assert.deepEqual(many.requests.map(x => Number(new URLSearchParams(x.split('?')[1]).get('offset'))),
                   [0, 1000, 2000]);
  assert.ok(many.requests.every(x => x.includes('order=ts.asc,id.asc')));

  const few = fixture({ reservas: reservations.slice(0, 30), suscriptoras: [], asistencias: [] });
  await few.context.sincronizarReservas();
  assert.equal(few.requests.length, 1);
  assert.equal(Object.values(few.context.SLOTS).flat().length, 30);

  const oldSchema = fixture({ reservas: reservations.slice(0, 1020), suscriptoras: [], asistencias: [] }, 'cancelada');
  await oldSchema.context.sincronizarReservas();
  assert.equal(oldSchema.context.COL_CANCELADA, false);
  assert.equal(Object.values(oldSchema.context.SLOTS).flat().length, 1020);
  assert.equal(oldSchema.requests.length, 3);

  const subs = Array.from({ length: 1100 }, (_, id) => ({ id: `SUB-${id}` }));
  const asist = Array.from({ length: 1200 }, (_, id) => ({
    id, clase: 'essenza', fecha: '2026-11-09', hora: '19:30',
    email: `a${id}@example.com`, asistio: id % 2 === 0
  }));
  const other = fixture({ reservas: [], suscriptoras: subs, asistencias: asist });
  await other.context.sincronizarSubs();
  await other.context.sincronizarAsistencias();
  assert.equal(other.context.SUBS.length, 1100);
  assert.equal(other.context.ASIST.size, 1200);
  assert.equal(other.context.ASIST.get('essenza_2026-11-09_19:30_a1199@example.com'), false);
  assert.equal(other.requests.length, 4);

  console.log('OK: reservas, suscriptoras y asistencias completas con paginación y esquemas anteriores.');
})().catch(error => { console.error(error); process.exitCode = 1; });
