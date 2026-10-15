const accountId = process.env.CLOUDFLARE_ACCOUNT_ID?.trim();
const apiToken = process.env.CLOUDFLARE_API_TOKEN?.trim();

if (!accountId || !/^[a-f0-9]{32}$/i.test(accountId)) {
  console.error('CLOUDFLARE_ACCOUNT_ID eksik veya biçimi geçersiz. Cloudflare dashboard hesabındaki Account ID değerini ayarla.');
  process.exit(2);
}
if (!apiToken) {
  console.error('CLOUDFLARE_API_TOKEN bulunamadı. Workers AI erişim yetkili tokenı ayarla.');
  process.exit(2);
}

const payload = {
  model: 'clef-flash',
  state: 'Integration smoke test. Water freezes at 0 degrees Celsius under standard atmospheric pressure.',
  questions: {
    test_ok: {
      type: 'noul',
      instructions: 'Is the statement generally true under standard atmospheric pressure?',
    },
  },
};

try {
  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/@cf/cloudflare/clef-flash`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiToken}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(30_000),
  });

  let data;
  try { data = await response.json(); } catch {
    console.error(`Clef API testi geçerli JSON döndürmedi (HTTP ${response.status}).`);
    process.exit(1);
  }

  if (!response.ok || data?.success === false) {
    if (response.status === 401) console.error('Cloudflare kimlik doğrulaması reddedildi (401). Tokenı kontrol et.');
    else if (response.status === 403) console.error('Erişim reddedildi (403). Tokenın Account > Workers AI > Read yetkisini ve model erişimini kontrol et.');
    else if (response.status === 429) console.error('Cloudflare 429 döndürdü: ücretsiz günlük Neuron tahsisi dolmuş veya kapasite sınırı olabilir.');
    else console.error(`Clef API testi başarısız (HTTP ${response.status}). ${Array.isArray(data?.errors) ? data.errors.map(x => x?.message ?? '').join(' ').slice(0, 300) : ''}`);
    process.exit(1);
  }

  const result = data?.result && typeof data.result === 'object' ? data.result : data;
  if (!result?.answers?.test_ok) {
    console.error('Clef API erişilebilir görünüyor ancak beklenen answers alanı dönmedi.');
    process.exit(1);
  }
  console.log(JSON.stringify({
    ok: true,
    provider: 'cloudflare-workers-ai',
    model: result.model ?? '@cf/cloudflare/clef-flash',
    answer: result.answers.test_ok,
    usage: result.usage ?? null,
  }, null, 2));
} catch (error) {
  console.error(`Clef API testi başarısız: ${error?.name === 'TimeoutError' ? 'Zaman aşımı.' : 'Bağlantı kurulamadı.'}`);
  process.exit(1);
}
