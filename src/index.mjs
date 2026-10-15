import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';

const API_URL = 'https://opencode.ai/zen/v1/systemone';
const MODEL = 'jev-1.13-free';
const REQUEST_TIMEOUT_MS = 30_000;
const MAX_RETRIES = 2;
const MAX_STATE_CHARS = 16_000;
const MAX_QUESTIONS_JSON_CHARS = 12_000;

class JevApiError extends Error {
  constructor(message, status = undefined) {
    super(message);
    this.name = 'JevApiError';
    this.status = status;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function retryDelay(response, attempt) {
  const retryAfter = response?.headers?.get('retry-after');
  if (retryAfter) {
    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds) && seconds >= 0) {
      return Math.min(seconds * 1000, 5_000);
    }
    const dateDelay = Date.parse(retryAfter) - Date.now();
    if (Number.isFinite(dateDelay) && dateDelay > 0) return Math.min(dateDelay, 5_000);
  }
  return Math.min(750 * (2 ** attempt), 3_000);
}

function validateQuestionsJson(raw) {
  let questions;
  try {
    questions = JSON.parse(raw);
  } catch {
    throw new Error('questions_json geçerli JSON değil. Her soru için type ve instructions alanları gerekir.');
  }

  if (!questions || typeof questions !== 'object' || Array.isArray(questions)) {
    throw new Error('questions_json üst düzeyde bir JSON nesnesi olmalı.');
  }

  const entries = Object.entries(questions);
  if (entries.length < 1 || entries.length > 20) {
    throw new Error('Bir istekte 1–20 arasında soru gönderebilirsin.');
  }

  for (const [id, question] of entries) {
    if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(id)) {
      throw new Error(`Geçersiz soru kimliği: ${id}. Harfle başlamalı; harf, rakam, _ ve - içerebilir.`);
    }
    if (!question || typeof question !== 'object' || Array.isArray(question)) {
      throw new Error(`'${id}' sorusu bir nesne olmalı.`);
    }
    if (!['noul', 'choice', 'score'].includes(question.type)) {
      throw new Error(`'${id}' için type 'noul', 'choice' veya 'score' olmalı.`);
    }
    if (typeof question.instructions !== 'string' || question.instructions.trim().length < 5 || question.instructions.length > 2_000) {
      throw new Error(`'${id}'.instructions 5–2000 karakterlik bir metin olmalı.`);
    }

    if (question.type === 'choice') {
      const criteria = question.criteria;
      if (!criteria || typeof criteria !== 'object' || Array.isArray(criteria)) {
        throw new Error(`'${id}' choice sorusu için criteria, etiket-açıklama eşlemesi olan bir nesne olmalı.`);
      }
      const options = Object.entries(criteria);
      if (options.length < 2 || options.length > 20) {
        throw new Error(`'${id}' choice sorusunda 2–20 seçenek bulunmalı.`);
      }
      for (const [key, label] of options) {
        if (!/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(key) || typeof label !== 'string' || !label.trim() || label.length > 500) {
          throw new Error(`'${id}' sorusunda her criteria anahtarı geçerli ve her açıklama 1–500 karakter olmalı.`);
        }
      }
    }

    if (question.type === 'score') {
      const criteria = question.criteria;
      const validArray = Array.isArray(criteria) && criteria.length >= 2 && criteria.length <= 20 && criteria.every((item) => typeof item === 'string' && item.trim() && item.length <= 500);
      const validObject = criteria && typeof criteria === 'object' && !Array.isArray(criteria) && Object.keys(criteria).length >= 2 && Object.keys(criteria).length <= 20 && Object.values(criteria).every((item) => typeof item === 'string' && item.trim() && item.length <= 500);
      if (!validArray && !validObject) {
        throw new Error(`'${id}' score sorusu için en az iki ölçüt içeren bir criteria dizisi veya nesnesi olmalı.`);
      }
    }
  }

  return questions;
}

async function requestJev(state, questions) {
  const apiKey = process.env.OPENCODE_API_KEY;
  if (!apiKey || !apiKey.trim()) {
    throw new JevApiError('OPENCODE_API_KEY bulunamadı. Windows kullanıcı ortam değişkenini ayarla ve Claude Code’u yeniden başlat.');
  }

  const payload = { model: MODEL, state, questions };
  let lastNetworkError;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt += 1) {
    let response;
    try {
      response = await fetch(API_URL, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
    } catch (error) {
      if (error?.name === 'TimeoutError' || error?.name === 'AbortError') {
        throw new JevApiError(`Jev isteği ${REQUEST_TIMEOUT_MS / 1000} saniyede zaman aşımına uğradı.`, undefined);
      }
      lastNetworkError = error;
      throw new JevApiError('Jev API bağlantısı kurulamadı. İnternet bağlantısını ve OpenCode Zen erişimini kontrol et.');
    }

    if (response.ok) {
      let data;
      try {
        data = await response.json();
      } catch {
        throw new JevApiError('Jev API geçerli JSON yanıtı döndürmedi.', response.status);
      }
      if (!data || typeof data !== 'object' || !data.answers || typeof data.answers !== 'object') {
        throw new JevApiError('Jev API yanıtı beklenen answers alanını içermiyor.', response.status);
      }
      return {
        model: data.model ?? MODEL,
        answers: data.answers,
        usage: data.usage ?? null,
      };
    }

    if ((response.status === 429 || response.status === 529) && attempt < MAX_RETRIES) {
      await sleep(retryDelay(response, attempt));
      continue;
    }

    const status = response.status;
    if (status === 401 || status === 403) {
      throw new JevApiError('OpenCode Zen kimlik doğrulaması reddedildi. OPENCODE_API_KEY değerini kontrol et.', status);
    }
    if (status === 402) {
      throw new JevApiError('API isteği ödeme/erişim gereksinimi nedeniyle reddedildi. Ücretsiz modele erişimin ve Zen hesabının durumunu kontrol et; otomatik olarak ücretli modele geçilmedi.', status);
    }
    if (status === 422) {
      throw new JevApiError('Jev isteği reddedildi (422). Soru türlerini, instructions alanlarını ve criteria biçimini kontrol et.', status);
    }
    if (status === 429) {
      throw new JevApiError('Jev ücretsiz kullanım limiti veya hız sınırı aşıldı (429). Daha sonra yeniden dene; ücretli modele geçilmedi.', status);
    }
    if (status === 529) {
      throw new JevApiError('Jev şu anda aşırı yük altında (529). Bir süre sonra yeniden dene; ücretli modele geçilmedi.', status);
    }
    if (status >= 500) {
      throw new JevApiError(`Jev API sunucu hatası döndürdü (${status}). Daha sonra yeniden dene.`, status);
    }
    throw new JevApiError(`Jev API isteği başarısız oldu (HTTP ${status}). İstek alanlarını ve erişim durumunu kontrol et.`, status);
  }

  throw new JevApiError(lastNetworkError ? 'Jev API bağlantısı kurulamadı.' : 'Jev API isteği başarısız oldu.');
}

function jsonToolResult(data) {
  return {
    content: [{ type: 'text', text: JSON.stringify(data, null, 2) }],
  };
}

function errorToolResult(error) {
  const message = error instanceof Error ? error.message : 'Bilinmeyen Jev hatası.';
  // API keys and request bodies are intentionally never included in error output.
  return {
    isError: true,
    content: [{ type: 'text', text: `Jev MCP hatası: ${message}` }],
  };
}

const server = new McpServer({
  name: 'jev-bridge',
  version: '1.0.0',
});

server.registerTool(
  'jev_assess',
  {
    title: 'Jev Structured Assessment',
    description: 'Evaluate a supplied state/context with Jev 1.13 Free using typed noul, choice, or score questions. Returns structured answers and token usage. This is a decision-support signal, not proof or a substitute for testing/security review.',
    inputSchema: z.object({
      state: z.string().min(1).max(MAX_STATE_CHARS).describe('Context for Jev to evaluate. Do not include secrets, API keys, .env contents, or unnecessary private data.'),
      questions_json: z.string().min(2).max(MAX_QUESTIONS_JSON_CHARS).describe('JSON object mapping question IDs to {type, instructions, criteria?}. Supported types: noul, choice, score.'),
    }),
  },
  async ({ state, questions_json }) => {
    try {
      const questions = validateQuestionsJson(questions_json);
      const result = await requestJev(state, questions);
      return jsonToolResult(result);
    } catch (error) {
      return errorToolResult(error);
    }
  },
);

server.registerTool(
  'jev_code_triage',
  {
    title: 'Jev Code Change Triage',
    description: 'Classify a user-provided code-change summary and test summary using Jev 1.13 Free. Jev does not read the repository or run tests itself; the supplied summaries are the only evidence. Never treat its output as a definitive security verdict.',
    inputSchema: z.object({
      change_summary: z.string().min(1).max(6_000).describe('Short summary of the intended code changes. Do not paste secrets.'),
      files_or_diff_summary: z.string().min(1).max(6_000).describe('Relevant filenames and a concise diff summary; do not send entire repositories.'),
      test_results: z.string().min(1).max(4_000).describe('Actual tests run and their results, or explicitly state that tests were not run.'),
    }),
  },
  async ({ change_summary, files_or_diff_summary, test_results }) => {
    try {
      const state = [
        'TASK: Triage a software change using only the evidence supplied below.',
        'IMPORTANT: Do not assume files were inspected or tests were executed beyond the explicit inputs. Missing information should increase caution.',
        `CHANGE SUMMARY:\n${change_summary}`,
        `FILES / DIFF SUMMARY:\n${files_or_diff_summary}`,
        `TEST RESULTS:\n${test_results}`,
      ].join('\n\n');

      const questions = {
        security_concern: {
          type: 'noul',
          instructions: 'Based only on the supplied summaries, is there a plausible security, privacy, authentication, authorization, or secret-handling concern that merits explicit human review?',
        },
        priority: {
          type: 'choice',
          instructions: 'Based only on the supplied summaries, what review priority is most appropriate? Use high for security-sensitive, data-loss, auth, broad architectural, or critical release changes; medium for behavior/API/dependency changes or meaningful test gaps; low for isolated low-impact documentation or formatting changes.',
          criteria: {
            low: 'Low-impact, isolated change with low apparent consequence.',
            medium: 'Meaningful behavioral change, dependency/interface change, or non-critical test gap.',
            high: 'Potential security/privacy/data-loss issue, critical behavior, broad change, or serious test failure.',
          },
        },
        regression_concern: {
          type: 'noul',
          instructions: 'Do the supplied summaries indicate a plausible regression concern, such as behavior changes, broad refactoring, interface/dependency changes, or failed/missing relevant tests?',
        },
        human_review_recommended: {
          type: 'noul',
          instructions: 'Should a human review the actual diff and relevant test results before merging or releasing, given the provided evidence and uncertainty?',
        },
      };

      const result = await requestJev(state, questions);
      return jsonToolResult({
        ...result,
        note: 'Jev evaluated only the summaries supplied to this tool. It did not inspect repository files or execute tests. Confirm conclusions using real code review and test output.',
      });
    } catch (error) {
      return errorToolResult(error);
    }
  },
);

// stdout is reserved for MCP JSON-RPC. Never use console.log in this process.
await serveStdio(() => server);
