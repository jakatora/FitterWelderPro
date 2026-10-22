// Actual Flutter HTTP bodies -> real local Express/SQLite -> injected provider.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
const root=process.cwd(),backend=path.resolve(process.argv[2]||'backend');
const load=p=>import(pathToFileURL(path.join(backend,p)).href);
const {startTestServer,api,newDeviceId,newSecret}=await load('test/helpers/server.js');
const server=await startTestServer();
try {
 const {fakeAnthropic}=await load('test/helpers/fakes.js');
 const {setAnthropicClientForTests}=await load('src/services/anthropicClient.js');
 const {budgetState}=await load('src/services/aiBudget.js');
 const fake=fakeAnthropic(()=>({stop_reason:'end_turn',usage:{input_tokens:1000,output_tokens:100},content:[{type:'text',text:'Fixture answer'}]}));
 setAnthropicClientForTests(fake.client);
 const results=[];
 for(const name of ['text-normal','voice-normal','text-retry','voice-retry']) {
  const raw=fs.readFileSync(path.join(root,`build/clarified-knowledge-wire-${name}.json`),'utf8');
  const captured=JSON.parse(raw),headers={'x-device-id':newDeviceId(),'x-install-secret':newSecret()};
  // Only installation identity is rebound to the isolated verifier database.
  const body={...captured,device_id:headers['x-device-id']};
  assert.equal((await api(server.base,'POST','/api/fitter/device/register',{headers,body:{}})).status,201);
  const before=fake.calls.length;
  const r=await api(server.base,'POST','/api/fitter/ai/chat',{headers,body});
  assert.equal(r.status,200,r.text);assert.equal(r.json.question_clarification_used,true);
  assert.equal(r.json.calculator_context_used,true);assert.equal(fake.calls.length,before+1);
  const call=fake.calls.at(-1),sent=JSON.parse(call.messages.at(-1).content);
  assert.deepEqual(sent.question_clarification,captured.question_clarification);
  assert.deepEqual(sent.calculator_context,captured.calculator_context);assert.equal(sent.question,captured.message);
  assert.equal(call.model,'claude-haiku-5-5');assert.equal(call.output_config.effort,'low');
  assert.deepEqual(fake.requestOptions.at(-1),{maxRetries:0,timeout:25000});assert.equal(budgetState().inFlightUsd,0);
  assert.ok(r.json.citations.some(c=>/interpass|międzyściegow/i.test(c)));
  results.push({name,utf8Bytes:Buffer.byteLength(raw),priorUserTurns:captured.question_clarification.user_turns.length,status:r.status});
 }
 const proof={checkedAt:new Date().toISOString(),backendHead:execFileSync('git',['rev-parse','HEAD'],{cwd:backend,encoding:'utf8'}).trim(),provider:'injected; no paid calls',results};
 fs.writeFileSync(path.join(root,'build/clarified-knowledge-wire-proof.json'),JSON.stringify(proof,null,2));console.log(JSON.stringify(proof));
} finally {await server.close();}
