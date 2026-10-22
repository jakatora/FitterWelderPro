// Actual Flutter chat-service request -> local Express/SQLite -> fake provider.
// The synthetic installation ID is replaced by the registered test identity.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
const heat=process.argv.includes('--heat-result');
const rolling=process.argv.includes('--rolling-result');
const slope=process.argv.includes('--slope-result');
assert.ok([heat,rolling,slope].filter(Boolean).length<=1,'Choose one result fixture');
const backend=path.resolve('backend');
const load=p=>import(pathToFileURL(path.join(backend,p)).href);
const {startTestServer,api,newDeviceId,newSecret}=await load('test/helpers/server.js');
const server=await startTestServer();
try {
 const {fakeAnthropic}=await load('test/helpers/fakes.js');
 const {setAnthropicClientForTests}=await load('src/services/anthropicClient.js');
 const {budgetState}=await load('src/services/aiBudget.js');
 const fixture=heat?'build/assistant-heat-result-widget-wire.json':rolling?'build/assistant-rolling_offset-result-widget-wire.json':slope?'build/assistant-pipe_slope-result-widget-wire.json':'build/assistant-calculator-chat-widget-wire.json';
 const request=JSON.parse(fs.readFileSync(fixture,'utf8'));
 const context=request.calculator_context;
 if(heat) {
  assert.equal(context.tool_id,'heat_input');
  assert.deepEqual(context.inputs,{process:'GTAW',standard:'en1011',volts:24,amps:230,travel_mm_min:150});
  assert.ok(Math.abs(context.results.value_kj_per_mm-1.3248)<1e-12);
  assert.deepEqual({...context.results,value_kj_per_mm:1.3248},{value_kj_per_mm:1.3248,display_value:1.32,display_unit:'kjPerMm',efficiency_used:0.6,efficiency_source:'process_default'});
 } else if(slope) {
  assert.equal(context.tool_id,'pipe_slope');
  assert.deepEqual(context.inputs,{mode:'length_to_rise',length_mm:6000,slope_pct:1});
  assert.deepEqual(context.results,{precision:'displayed',length_mm:6000,rise_mm:60,slope_pct:1,angle_deg:0.573,mm_per_m:10});
 } else {
  assert.equal(context.tool_id,'rolling_offset');
  assert.deepEqual(context.inputs,{rise_mm:300,spread_mm:400,angle_deg:45,dn:rolling?100:50,gap_mm:rolling?3:2});
  assert.equal(context.results.precision,'displayed');
  assert.equal(context.results.true_offset_mm,500);assert.equal(context.results.travel_mm,707.1);
  assert.equal(context.results.cut_elbows_overlap,false);
  if(rolling) {assert.equal(context.results.takeout_mm,64);assert.equal(context.results.cut_mm,573.1);}
 }
 const fake=fakeAnthropic(()=>({stop_reason:'end_turn',usage:{input_tokens:1000,output_tokens:100},content:[{type:'text',text:'Fixture calculator explanation'}]}));
 setAnthropicClientForTests(fake.client);
 const headers={'x-device-id':newDeviceId(),'x-install-secret':newSecret()};
 assert.equal((await api(server.base,'POST','/api/fitter/device/register',{headers,body:{}})).status,201);
 const response=await api(server.base,'POST','/api/fitter/ai/chat',{headers,body:{...request,device_id:headers['x-device-id']}});
 assert.equal(response.status,200,response.text);assert.equal(response.json.calculator_context_used,true);
 assert.match(response.json.text,/Fixture calculator explanation/);
 assert.equal(fake.calls.length,1);
 const call=fake.calls[0],sent=JSON.parse(call.messages.at(-1).content);
 assert.deepEqual(sent.calculator_context,context);assert.equal(sent.question,request.message);
 assert.equal(call.model,'claude-haiku-5-5');assert.equal(call.output_config.effort,'low');
 assert.deepEqual(fake.requestOptions[0],{maxRetries:0,timeout:25000});
 assert.equal(budgetState().inFlightUsd,0);
 const proof={checkedAt:new Date().toISOString(),backendHead:execFileSync('git',['rev-parse','HEAD'],{cwd:backend,encoding:'utf8'}).trim(),tool:context.tool_id,contextBytes:Buffer.byteLength(JSON.stringify(context)),status:response.status,provider:'injected fake; zero paid calls'};
 const output=heat?'build/assistant-heat-result-backend-proof.json':rolling?'build/assistant-rolling-result-backend-proof.json':slope?'build/assistant-slope-result-backend-proof.json':'build/assistant-calculator-context-backend-proof.json';
 fs.writeFileSync(output,JSON.stringify(proof,null,2));
 console.log(JSON.stringify(proof));
} finally {await server.close();}
