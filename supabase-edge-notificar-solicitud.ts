// ═══════════════════════════════════════════════════════════════════
//  PRESENZA STUDIO · Edge Function "notificar-solicitud"
//  Deno.serve — pegar en Supabase → Edge Functions → New Function
//
//  QUÉ HACE
//  La llama cualquier visitante que pide un plan nuevo desde el sitio —
//  sin haber iniciado sesión, cualquiera puede tocar este botón. Reemplaza
//  el fetch directo a formsubmit.co que había antes: ahora el correo sale
//  por Resend, con el remitente propio de Presenza.
//
//  POR QUÉ EL DESTINATARIO ESTÁ FIJO EN EL CÓDIGO Y NO EN EL PEDIDO
//  Como cualquiera sin sesión puede llamarla, si el destinatario viniera
//  en el body del POST, cualquiera podría armar el pedido a mano y usar
//  esta función como reenviador gratis de correo hacia quien quiera —
//  un relay de spam con el nombre de Presenza. Por eso `para` no se lee
//  del pedido: SIEMPRE es EMAIL_ESTUDIO. Lo único que decide quien llama
//  es el asunto y la tabla de datos que se muestran adentro.
//
//  REPLY-TO AL CORREO DE LA ALUMNA
//  Si el pedido trae un correo de contacto (datos.Email), se pone ahí:
//  cuando el estudio le da "Responder" a este aviso, le llega directo a
//  ella, no se pierde. Antes, con FormSubmit, no había forma de hacer eso.
//
//  QUÉ HAY QUE CONFIGURAR (una sola vez)
//  1. Crear esta función con el nombre EXACTO "notificar-solicitud".
//  2. En Project Settings → Edge Functions → Secrets, agregar
//     RESEND_API_KEY con la llave de Resend (la que empieza "re_").
//     SUPABASE_URL y SUPABASE_ANON_KEY ya existen solas, no hace falta
//     agregarlas.
//  3. El dominio presenzastudioni.com tiene que estar "Verified" en
//     Resend — si no, Resend rechaza el envío con un error claro.
// ═══════════════════════════════════════════════════════════════════

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!;
const REMITENTE      = 'Presenza Studio <reservas@presenzastudioni.com>';
const EMAIL_ESTUDIO  = 'presenza.studio@outlook.com';

// El sitio corre en un solo origen; nadie más debería poder invocar esto
// desde un navegador. Las llamadas servidor-a-servidor (curl, Postman) no
// mandan Origin y no las bloquea esto — para esas, el filtro real es que
// el destinatario está fijo abajo, así que lo peor que logran es mandarse
// un correo a sí mismos con datos inventados.
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': 'https://presenzastudioni.com',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]!));
}

// Misma idea que el "_template: table" de FormSubmit, pero escrita a mano:
// Resend no tiene esa magia, así que la tabla se arma acá.
function tablaHtml(datos: Record<string, unknown>): string {
  const filas = Object.entries(datos || {}).map(([k, v]) => `
    <tr>
      <td style="padding:7px 14px;color:#6B1728;font-weight:600;white-space:nowrap;border-bottom:1px solid #eee">${escapeHtml(k)}</td>
      <td style="padding:7px 14px;border-bottom:1px solid #eee">${escapeHtml(String(v ?? ''))}</td>
    </tr>`).join('');
  return `<table style="border-collapse:collapse;font-family:sans-serif;font-size:14px;width:100%;max-width:480px">${filas}</table>`;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ ok: false, error: 'method not allowed' }),
      { status: 405, headers: CORS_HEADERS });
  }

  try {
    const { asunto, datos } = await req.json();
    if (!asunto || typeof asunto !== 'string') {
      return new Response(JSON.stringify({ ok: false, error: 'falta el asunto' }),
        { status: 400, headers: CORS_HEADERS });
    }

    const replyTo = typeof datos?.Email === 'string' && datos.Email.includes('@') ? datos.Email : undefined;

    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: REMITENTE,
        to: [EMAIL_ESTUDIO],           // fijo — ver nota arriba
        reply_to: replyTo,
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
