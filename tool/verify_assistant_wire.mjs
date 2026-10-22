// Cross-runtime contract check: Flutter-generated catalog -> real Express/SQLite
// -> injected provider. Fake credentials and closed provider port prevent billing.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
const backend = path.resolve(process.argv[2] || 'backend');
const root = process.cwd();
const load = relative => import(pathToFileURL(path.join(backend, relative)).href);
const {startTestServer, api, newDeviceId, newSecret} = await load('test/helpers/server.js');
const server = await startTestServer();
try {
  const {fakeAnthropic} = await load('test/helpers/fakes.js');
  const {setAnthropicClientForTests} = await load('src/services/anthropicClient.js');
  const {budgetState} = await load('src/services/aiBudget.js');
  const proposal = lang => ({kind:'execute', steps:[{skill_id:'development.summary',
    command:lang === 'en' ? 'Summarize current development' : 'Podsumuj bieżące rozwinięcie'}], message:''});
  const fake = fakeAnthropic(params => ({stop_reason:'end_turn',usage:{input_tokens:2000,output_tokens:100},
    content:[{type:'text',text:JSON.stringify(proposal(JSON.parse(params.messages[0].content).lang))}]}));
  setAnthropicClientForTests(fake.client);
  const results = [];
  for (const lang of ['pl','en']) {
    const raw = fs.readFileSync(path.join(root,`build/assistant-full-wire-${lang}.json`),'utf8');
    const request = JSON.parse(raw);
    const headers = {'x-device-id':newDeviceId(),'x-install-secret':newSecret()};
    assert.equal((await api(server.base,'POST','/api/fitter/device/register',{headers,body:{}})).status,201);
    const response = await api(server.base,'POST','/api/fitter/ai/assistant',{headers,body:request});
    assert.equal(response.status,200,response.text);
    assert.deepEqual(response.json,proposal(lang));
    const call = fake.calls.at(-1), sent = JSON.parse(call.messages[0].content);
    assert.equal(sent.lang,lang);
    assert.deepEqual(sent.capabilities,request.capabilities);
    assert.deepEqual(sent.context.inputs,request.context.inputs);
    assert.equal(call.model,'claude-haiku-5-5');
    assert.equal(call.output_config.effort,'low');
    assert.deepEqual(fake.requestOptions.at(-1),{maxRetries:0,timeout:25000});
    assert.equal(budgetState().inFlightUsd,0);
    results.push({lang,capabilities:request.capabilities.length,utf8Bytes:Buffer.byteLength(raw),status:response.status});
  }
  assert.equal(fake.calls.length,2);
  const proof = {checkedAt:new Date().toISOString(),backendHead:execFileSync('git',['rev-parse','HEAD'],{cwd:backend,encoding:'utf8'}).trim(),
    provider:'injected fake; no paid calls',results};
  fs.writeFileSync(path.join(root,'build/assistant-wire-backend-proof.json'),JSON.stringify(proof,null,2));
  console.log(JSON.stringify(proof));
} finally { await server.close(); }
