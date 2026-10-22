// Flutter-captured task-switch request through real local Express/SQLite.
// Injected provider only: no paid API calls. Run the task-switch widget tests first.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
const navigation = process.argv.includes('--navigation');
const knowledge = process.argv.includes('--knowledge');
const signOut = process.argv.includes('--sign-out');
assert.ok([navigation, knowledge, signOut].filter(Boolean).length <= 1, 'Choose one fixture mode');
const skillId = signOut ? 'account.sign_out' : knowledge ? 'iso.draw' : navigation ? 'tool.open' : 'iso.summary.copy';
const command = signOut ? 'Wyloguj mnie' : navigation ? 'Otwórz heat input' : 'Skopiuj zestawienie rysunku ISO';
const fixture = signOut ? 'build/assistant-account-signout-wire.json' : knowledge ? 'build/assistant-pending-knowledge-wire.json' : navigation ? 'build/assistant-navigation-wire.json' : 'build/assistant-task-switch-wire.json';
const proofPath = signOut ? 'build/assistant-account-signout-backend-proof.json' : knowledge ? 'build/assistant-pending-knowledge-backend-proof.json' : navigation ? 'build/assistant-navigation-backend-proof.json' : 'build/assistant-task-switch-backend-proof.json';
const backend = path.resolve('backend');
const load = relative => import(pathToFileURL(path.join(backend,relative)).href);
const {startTestServer,api,newDeviceId,newSecret}=await load('test/helpers/server.js');
const server=await startTestServer();
try {
  const {fakeAnthropic}=await load('test/helpers/fakes.js');
  const {setAnthropicClientForTests}=await load('src/services/anthropicClient.js');
  const {budgetState}=await load('src/services/aiBudget.js');
  const request=JSON.parse(fs.readFileSync(fixture,'utf8'));
  assert.equal(request.capabilities.length,1);
  assert.equal(request.capabilities[0].id,skillId);
  assert.equal(request.context.active_tool,signOut ? 'rolling_offset' : 'iso_notebook');
  if (knowledge) {
    assert.equal(request.context.pending_reply.skill_id,'iso.draw');
    assert.ok(request.context.pending_question.length > 0);
  } else {
    assert.equal(request.context.pending_reply,undefined);
    assert.equal(request.context.pending_question,null);
  }
  const proposal=knowledge ? {kind:'answer',steps:[],message:''} : {kind:'execute',steps:[{skill_id:skillId,command}],message:''};
  const fake=fakeAnthropic(()=>({stop_reason:'end_turn',usage:{input_tokens:1500,output_tokens:100},content:[{type:'text',text:JSON.stringify(proposal)}]}));
  setAnthropicClientForTests(fake.client);
  const headers={'x-device-id':newDeviceId(),'x-install-secret':newSecret()};
  assert.equal((await api(server.base,'POST','/api/fitter/device/register',{headers,body:{}})).status,201);
  const response=await api(server.base,'POST','/api/fitter/ai/assistant',{headers,body:request});
  assert.equal(response.status,200,response.text);
  assert.deepEqual(response.json,proposal);
  assert.equal(fake.calls.length,1);
  assert.equal(fake.calls[0].model,'claude-haiku-5-5');
  assert.equal(fake.calls[0].output_config.effort,'low');
  const sent=JSON.parse(fake.calls[0].messages[0].content);
  assert.deepEqual(sent.capabilities,request.capabilities);
  assert.deepEqual(sent.context.pending_reply,request.context.pending_reply);
  assert.deepEqual(fake.requestOptions[0],{maxRetries:0,timeout:25000});
  assert.equal(budgetState().inFlightUsd,0);
  const proof={checkedAt:new Date().toISOString(),backendHead:execFileSync('git',['rev-parse','HEAD'],{cwd:backend,encoding:'utf8'}).trim(),capabilities:1,bytes:Buffer.byteLength(JSON.stringify(request)),status:response.status,provider:'injected fake; zero paid calls'};
  fs.writeFileSync(proofPath,JSON.stringify(proof,null,2));
  console.log(JSON.stringify(proof));
} finally {await server.close();}
