// REAL model check: Flutter-generated catalog -> local Express/SQLite backend
// -> the real Anthropic API with the Fitter Welder Pro project key and a hard
// budget gate. Unlike the other verify_*_wire scripts this one IS billed —
// a few dozen short calls to Claude Haiku. It measures what the fakes cannot:
// whether the model picks the right capability for natural Polish speech.
//
// Usage (the key never appears on the command line or in the output):
//   FWP_REAL_ANTHROPIC_KEY=<from Railway> node tool/verify_assistant_real_haiku.mjs backend
// Optional: FWP_REAL_BUDGET_USD (default 1.00).
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';

const key = process.env.FWP_REAL_ANTHROPIC_KEY;
if (!key || key.length < 20) {
  console.error('FWP_REAL_ANTHROPIC_KEY missing — nothing was called.');
  process.exit(2);
}
const backend = path.resolve(process.argv[2] || 'backend');
const root = process.cwd();
const load = relative => import(pathToFileURL(path.join(backend, relative)).href);
const budget = process.env.FWP_REAL_BUDGET_USD || '1.00';
const {startTestServer, api, newDeviceId, newSecret} = await load('test/helpers/server.js');
const server = await startTestServer({
  ANTHROPIC_API_KEY: key,
  ANTHROPIC_BASE_URL: 'https://api.anthropic.com',
  AI_BUDGET_HARD_USD: budget,
  AI_BUDGET_SOFT_USD: String(Number(budget) / 2),
});

// expect: list of accepted outcomes — 'skill.id' (first step of execute) or a
// kind ('clarify' | 'answer' | 'unsupported' | 'not-execute').
const CASES = [
  ['pl', 'ile ma średnicy zewnętrznej rura de en sto', ['pipe.od']],
  ['pl', 'jaka grubość ścianki dla dn 80 szedziul 40', ['pipe.wall']],
  ['pl', 'otwórz mi kalkulator spadku rury', ['tool.open', 'pipe.slope']],
  ['pl', 'ile waży sześć metrów rury dn 100 ścianka 4 mm nierdzewka', ['pipe.weight']],
  ['pl', 'przelicz trzy czwarte cala na milimetry', ['units.convert']],
  ['pl', 'dobierz mi filtr do przyłbicy na migomag 180 amper', ['shade.number']],
  ['pl', 'jaki wolfram do aluminium na sto pięćdziesiąt amper', ['tungsten.pick']],
  ['pl', 'policz energię liniową 25 wolt 200 amper prędkość 180 milimetrów na minutę', ['heat.input']],
  ['pl', 'narysuj mi rurę w prawo potem kolano w górę i znowu rurę', ['iso.draw']],
  ['pl', 'zapisz że spawam tigiem nierdzewkę dwa milimetry na sześćdziesiąt amper bez drutu', ['legacy.save']],
  ['pl', 'ile ton uniesie zielony pas', ['rigging.colour']],
  ['pl', 'dlaczego mam pory w spoinie przy migomagu na czarnej stali', ['defects.causes', 'answer']],
  ['pl', 'jakie spoiwo dać do stali 316L', ['filler.pick']],
  ['pl', 'kiedy mi wygasa uprawnienie na 141', ['certs.expiry']],
  ['pl', 'włącz stoper spawania', ['timer.start']],
  ['pl', 'ustaw chłodzenie na trzy minuty', ['timer.cool', 'timer.set']],
  ['pl', 'ile mi zostało gazu w butli dziesięć litrów sto pięćdziesiąt bar przepływ dwanaście litrów na minutę', ['gas.remaining']],
  ['pl', 'do czego służy rolling offset', ['tool.explain']],
  ['pl', 'co ty w ogóle potrafisz', ['assistant.capabilities']],
  ['pl', 'wymiar kolana dn 80 dziewięćdziesiąt stopni długi promień', ['elbow.takeout']],
  ['pl', 'rozwiń mi stożek duża średnica 500 mała 250 wysokość 300', ['cone.layout']],
  ['pl', 'przygotuj protokół prac pożarowo niebezpiecznych', ['hot_work.prepare']],
  ['pl', 'dodaj pomiar temperatury międzyściegowej 180 stopni', ['interpass.reading']],
  ['pl', 'jaki moment dokręcenia śruby trzy czwarte cala B7 na smarze', ['bolt.torque']],
  ['pl', 'jak po niemiecku jest spoina pachwinowa', ['glossary.term']],
  ['pl', 'jaki prąd mam zapisany do nierdzewki trzy milimetry', ['params.saved']],
  ['pl', 'ile cali średnic zrobiłem dzisiaj', ['progress.today']],
  ['pl', 'jaki jest nds dla manganu', ['fume.oel']],
  ['pl', 'nazwij rysunek linia para 12', ['iso.name']],
  ['pl', 'wyloguj mnie z konta', ['account.sign_out']],
  ['pl', 'zamów mi pizzę z dostawą', ['not-execute']],
  ['pl', 'policz', ['clarify', 'not-execute']],
  ['pl', 'ile to waży', ['clarify', 'not-execute']],
  ['en', 'what is the outside diameter of DN 50 pipe', ['pipe.od']],
  ['en', 'start the welding stopwatch', ['timer.start']],
  ['en', 'which filler wire for 316L stainless', ['filler.pick']],
  ['pl', 'ile zużyję gazu na dziesięć spoin po dwie minuty przy dwunastu litrach', ['gas.consumption']],
  ['pl', 'ile czasu formować rurę sześćdziesiąt koma trzy ścianka dwa metr długości', ['purge.estimate']],
  ['pl', 'zamień 250 HV na skalę Brinella', ['hardness.convert']],
  ['pl', 'policz t osiem pięć dla jeden kilodżul na milimetr podgrzanie sto grubość dwadzieścia', ['cooling.t85']],
  ['pl', 'równoważnik węgla węgiel 0,18 mangan 1,4 grubość 20', ['preheat.ce']],
  ['pl', 'spawarka ma na tabliczce 200 amper przy 60 procentach, jaki cykl przy 150', ['power.duty']],
  ['pl', 'czy przewód 35 mm kwadratowych na 30 metrów wytrzyma 250 amper', ['power.cable']],
  ['pl', 'jaki spadek na 12 metrach przy dwóch procentach', ['pipe.slope']],
  ['pl', 'rolling offset wznios 250 odsunięcie 300 kąt 45', ['rolling.offset']],
  ['pl', 'jaka dylatacja 30 metrów nierdzewki przy różnicy 80 stopni', ['thermal.expansion']],
  ['pl', 'policz kolano segmentowe 114 i trzy dziesiąte, 90 stopni, cztery segmenty', ['mitre.bend']],
  ['pl', 'ile waży dwuteownik IPE 160 sześć metrów', ['steel.weight']],
  ['pl', 'ile podtopienia dopuszcza ISO 5817 na poziomie C przy grubości 8', ['iso5817.limit']],
  ['pl', 'jak długo elektroda zasadowa może leżeć poza suszarką', ['electrodes.exposure']],
  ['pl', 'jaka była moja ostatnia spoina w dzienniku', ['journal.last']],
  ['pl', 'kiedy mam kalibrację przyrządów', ['instruments.due']],
  ['pl', 'zrób nową wycenę spawania', ['quote.new']],
  ['pl', 'przygotuj protokół wejścia do zbiornika', ['confined_space.prepare']],
  ['pl', 'podsumuj mi rysunek izometryczny', ['iso.summary']],
  ['pl', 'chcę się zarejestrować', ['account.open']],
  ['pl', 'jaki przepływ argonu ustawić do tiga', ['knowledge', 'answer']],
  ['pl', 'nie działa mi zapis wyceny, zgłoś to', ['unsupported']],
  ['pl', 'ta aplikacja jest bez sensu, rysunek mi się nie zapisuje', ['unsupported']],
  ['en', 'the slope calculator gives wrong results, please report it', ['unsupported']],
  ['pl', 'ile wyciąć na siodło rury pięćdziesiątki na setkę', ['saddle.cut']],
  ['pl', 'zrób mi szablon siodła 60 na 114 pod kątem 45 stopni', ['saddle.template']],
  ['pl', 'czy spoina a4 po sto milimetrów dwie strony S355 blacha 10 wytrzyma 150 kN', ['fillet.strength']],
  ['pl', 'ile się skurczy spoina V na blasze 10 mm kąt 60 szczelina 2 próg półtora', ['distortion.shrinkage']],
  ['pl', 'czy mogę dziś spawać na dworze jest minus 3 wilgotność 80 procent wiatr 5 metrów na sekundę migomag', ['weather.check']],
  ['pl', 'co ile dać podpory na rurze DN100 z wodą', ['pipe.supports']],
  ['pl', 'jaki prąd na tandem przy zbiorniku 3 mm na styk w poziomie', ['tandem.tig']],
  ['pl', 'jakie szpilki do kołnierza DN100 klasa 300 RF', ['bolt.kit']],
  ['pl', 'czy trzeba wyżarzać P91 30 mm według B31.1', ['pwht.plan']],
  ['pl', 'parametry orbitala na rurkę 25,4 ścianka 1,65', ['orbital.tig']],
  ['pl', 'spoina od środka wyszła niebieska, przejdzie?', ['heat_tint.check']],
  ['pl', 'jakie ciśnienie próby wodnej B31.3 przy 16 bar projektowego', ['pressure.test']],
  ['pl', 'ile mam brać za godzinę żeby mieć 10 tysięcy na rękę', ['hourly.rate']],
];

// FWP_REAL_ONLY=<fragment> — tylko pasujące przypadki, FWP_REAL_REPEAT=n powtórzeń.
const only = process.env.FWP_REAL_ONLY;
const repeat = Math.max(1, Number(process.env.FWP_REAL_REPEAT || 1));
const selected = CASES.filter(([, text]) => !only || only.split('|').some(o => text.includes(o)))
  .flatMap(c => Array(repeat).fill(c));
const template = JSON.parse(fs.readFileSync(path.join(root, 'build/assistant-full-wire-pl.json'), 'utf8'));
const results = [];
let failures = 0;
try {
  let headers;
  // Dzienny limit zapytań na urządzenie (ochrona kosztów) — korpus dłuższy
  // niż limit dostaje kolejne testowe urządzenie zamiast porażki 429.
  const freshDevice = async () => {
    headers = {'x-device-id': newDeviceId(), 'x-install-secret': newSecret()};
    const reg = await api(server.base, 'POST', '/api/fitter/device/register', {headers, body: {}});
    if (reg.status !== 201) throw new Error(`register ${reg.status}`);
  };
  await freshDevice();
  for (const [lang, text, expect] of selected) {
    const body = {
      ...template,
      text,
      lang,
      context: {active_tool: null, inputs: {}, pending_question: null, history: []},
    };
    const started = Date.now();
    let res = await api(server.base, 'POST', '/api/fitter/ai/assistant', {headers, body});
    if (res.status === 429) {
      await freshDevice();
      res = await api(server.base, 'POST', '/api/fitter/ai/assistant', {headers, body});
    }
    const ms = Date.now() - started;
    const json = res.json || {};
    const kind = json.kind ?? `http-${res.status}`;
    const skill = kind === 'execute' ? json.steps?.[0]?.skill_id : null;
    const steps = kind === 'execute' ? (json.steps || []).map(st => st.skill_id) : [];
    // Plan wielokrokowy (np. najpierw `tool.open`, potem właściwa umiejętność)
    // jest poprawny, jeśli oczekiwana umiejętność jest w krokach.
    // Zgłoszenie problemu aplikacja zapisuje dla twórcy — odmowa „nie mogę
    // zgłaszać” wprowadza użytkownika w błąd.
    const refusesReport = /nie mog\w* (?:zgłasza|zgłosić|przekaza)|cannot (?:report|pass on)/i
      .test(String(json.message || ''));
    const ok = res.status === 200 && !refusesReport && expect.some(e =>
      steps.includes(e) || e === kind || (e === 'not-execute' && kind !== 'execute'));
    if (!ok) failures++;
    results.push({lang, text, expect, status: res.status, kind, skill,
      steps,
      commands: kind === 'execute'
        ? (json.steps || []).map(st => ({skill_id: st.skill_id, command: st.command}))
        : [],
      message: typeof json.message === 'string' ? json.message.slice(0, 160) : null, ms, ok});
    console.log(`${ok ? 'OK  ' : 'FAIL'} ${kind}${skill ? `:${skill}` : ''}  <- ${text}`);
    if (res.status === 503) break; // budżet albo dostawca — nie mnożyć wywołań
  }
} finally {
  let usage = null;
  try {
    const {db} = await load('src/db/index.js');
    usage = db.prepare('SELECT COUNT(*) AS calls, ROUND(SUM(cost_usd), 6) AS cost_usd, ' +
      'SUM(input_tokens) AS input_tokens, SUM(output_tokens) AS output_tokens FROM ai_usage').get();
  } catch (e) { usage = {error: String(e.message || e)}; }
  const proof = {
    checkedAt: new Date().toISOString(),
    backendHead: execFileSync('git', ['rev-parse', 'HEAD'], {cwd: backend, encoding: 'utf8'}).trim(),
    provider: 'REAL Anthropic API (FWP project key), hard budget ' + budget + ' USD',
    cases: results.length, passed: results.length - failures, failures, usage, results,
  };
  fs.writeFileSync(path.join(root, 'build/assistant-real-haiku-proof.json'), JSON.stringify(proof, null, 2));
  console.log(JSON.stringify({cases: proof.cases, passed: proof.passed, failures, usage}));
  await server.close();
}
