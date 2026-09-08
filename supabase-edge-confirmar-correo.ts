// ═══════════════════════════════════════════════════════════════════
//  PRESENZA STUDIO · Edge Function "confirmar-correo"
//  Deno.serve — pegar en Supabase → Edge Functions → New Function
//
//  QUÉ HACE
//  La llama el panel cuando Jimena/Laura/Carlos confirman un pago —una
//  reserva suelta o un paquete pendiente— y le avisa a la alumna por
//  correo, ya con su clase o su plan activo. Reemplaza el fetch directo a
//  formsubmit.co: ahora sale por Resend, directo a ella (ya no "en copia"
//  de un correo que en realidad iba al estudio).
//
//  POR QUÉ ÉSTA SÍ PUEDE MANDAR A CUALQUIER DESTINATARIO
//  A diferencia de notificar-solicitud (pública, sin sesión), acá el
//  destinatario SÍ viene en el pedido — porque quien llama ya demostró
//  ser del estudio: el panel manda el token de la sesión de quien inició
//  sesión, y esta función lo verifica contra Supabase Auth antes de
//  mandar nada. Sin un token válido, responde 401 y no llega a tocar
//  Resend. Es el mismo candado que ya protege reservas/suscriptoras en
//  la base — acá se aplica al envío de correo.
//
//  REPLY-TO AL ESTUDIO
//  Si la alumna responde este correo, le llega a presenza.studio@outlook.com
//  —la bandeja de siempre—, no queda respondiendo al aire.
//
//  QUÉ HAY QUE CONFIGURAR (una sola vez)
//  1. Crear esta función con el nombre EXACTO "confirmar-correo".
//  2. Igual que notificar-solicitud: agregar el secreto RESEND_API_KEY
//     en Project Settings → Edge Functions → Secrets (si ya lo agregaste
//     para la otra función, es el mismo, no hay que repetirlo).
//  3. El dominio presenzastudioni.com tiene que estar "Verified" en Resend.
// ═══════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const RESEND_API_KEY   = Deno.env.get('RESEND_API_KEY')!;
const SUPABASE_URL     = Deno.env.get('SUPABASE_URL')!;       // la pone Supabase sola
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!; // la pone Supabase sola
const REMITENTE        = 'Presenza Studio <reservas@presenzastudioni.com>';
const EMAIL_ESTUDIO    = 'presenza.studio@outlook.com';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': 'https://presenzastudioni.com',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]!));
}

function tablaHtml(datos: Record<string, unknown>): string {
  const filas = Object.entries(datos || {}).map(([k, v]) => `
    <tr>
      <td style="padding:7px 14px;color:#6B1728;font-weight:600;white-space:nowrap;border-bottom:1px solid #eee">${escapeHtml(k)}</td>
      <td style="padding:7px 14px;border-bottom:1px solid #eee">${escapeHtml(String(v ?? ''))}</td>
    </tr>`).join('');
  return `<table style="border-collapse:collapse;font-family:sans-serif;font-size:14px;width:100%;max-width:480px">${filas}</table>`;
}

function emailValido(v: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i.test((v || '').trim());
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ ok: false, error: 'method not allowed' }),
      { status: 405, headers: CORS_HEADERS });
  }

  try {
    // ── El candado: sin sesión real de Supabase Auth, no pasa de acá ──
    // getUser() con el token que mandó el panel: si es la llave anon (una
    // visitante sin iniciar sesión) devuelve sin usuario, no un error —
    // por eso se revisa `!user`, no solo `error`.
    const auth = req.headers.get('Authorization') || '';
    const jwt  = auth.replace(/^Bearer\s+/i, '');
    const supa = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: auth } },
    });
    const { data: { user }, error: authError } = await supa.auth.getUser(jwt);
    if (authError || !user) {
      return new Response(JSON.stringify({ ok: false, error: 'Sin sesión válida del estudio' }),
        { status: 401, headers: CORS_HEADERS });
    }

    const { para, asunto, datos } = await req.json();
    if (!emailValido(para)) {
      return new Response(JSON.stringify({ ok: false, error: 'destinatario inválido' }),
        { status: 400, headers: CORS_HEADERS });
    }
    if (!asunto || typeof asunto !== 'string') {
      return new Response(JSON.stringify({ ok: false, error: 'falta el asunto' }),
        { status: 400, headers: CORS_HEADERS });
    }

    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: REMITENTE,
        to: [para],
        reply_to: EMAIL_ESTUDIO,
        subject: asunto,
        html: tablaHtml(datos),
      }),
    });

    if (!r.ok) {
      const detalle = await r.text();
      return new Response(JSON.stringify({ ok: false, error: `Resend ${r.status}: ${detalle}` }),
        { status: 502, headers: CORS_HEADERS });
    }
    return new Response(JSON.stringify({ ok: true }), { headers: CORS_HEADERS });

  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }),
      { status: 500, headers: CORS_HEADERS });
  }
});
