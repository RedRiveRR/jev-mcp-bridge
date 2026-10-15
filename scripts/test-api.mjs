const apiKey = process.env.OPENCODE_API_KEY;
if (!apiKey?.trim()) {
  console.error('OPENCODE_API_KEY bulunamadı. Önce install.ps1 çalıştır veya ortam değişkenini ayarla.');
  process.exit(2);
}

const payload = {
  model: 'jev-1.13-free',
  state: 'Integration smoke test. This statement is generally true: water freezes at 0 degrees Celsius under standard atmospheric pressure.',
  questions: {
    test_ok: {
      type: 'noul',
      instructions: 'Is the statement generally true under standard atmospheric pressure?',
    },
  },
};

try {
  const response = await fetch('https://opencode.ai/zen/v1/systemone', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(30_000),
  });

  if (!response.ok) {
    const guidance = response.status === 401 || response.status === 403
      ? 'Kimlik doğrulaması reddedildi; OPENCODE_API_KEY değerini kontrol et.'
      : response.status === 429
        ? 'Ücretsiz kullanım limiti/hız sınırı dolmuş olabilir. Ücretli modele geçiş yapılmadı.'
        : `HTTP ${response.status}; ücretsiz model erişimini ve API isteğini kontrol et.`;
    console.error(`Jev API testi başarısız: ${guidance}`);
    process.exit(1);
  }

  const data = await response.json();
  if (!data?.answers?.test_ok) {
    console.error('Jev API erişilebilir görünüyor ancak beklenen cevap alanı dönmedi.');
    process.exit(1);
  }
  console.log(JSON.stringify({
    ok: true,
    model: data.model,
    answer: data.answers.test_ok,
    usage: data.usage ?? null,
  }, null, 2));
} catch (error) {
  console.error(`Jev API testi başarısız: ${error?.name === 'TimeoutError' ? 'Zaman aşımı.' : 'Ağa bağlanılamadı.'}`);
  process.exit(1);
}
