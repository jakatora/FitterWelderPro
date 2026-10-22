// Actual Flutter-captured interpreter and confirmed-write bodies -> real local
// Express/SQLite. Provider alone is injected; no paid call or live profile edit.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
const backend=path.resolve('backend');
const load=p=>import(pathToFileURL(path.join(backend,p)).href);
const {startTestServer,api,newDeviceId,newSecret}=await load('test/helpers/server.js');
const server=await startTestServer();
try {
  const request=JSON.parse(fs.readFileSync('build/assistant-professional-profile-wire.json','utf8'));
  const write=JSON.parse(fs.readFileSync('build/assistant-professional-profile-write.json','utf8'));
  assert.equal(request.capabilities.length,1);
  assert.equal(request.capabilities[0].id,'account.professional.edit');
  assert.deepEqual(write,{field:'experienceYears',value:8,expected:4});
  const {fakeAnthropic}=await load('test/helpers/fakes.js');
  const {setAnthropicClientForTests}=await load('src/services/anthropicClient.js');
  const {budgetState}=await load('src/services/aiBudget.js');
  const proposal={kind:'execute',steps:[{skill_id:'account.professional.edit',command:'Ustaw w moim profilu doświadczenie na 8 lat'}],message:''};
  const fake=fakeAnthropic(()=>({stop_reason:'end_turn',usage:{input_tokens:1500,output_tokens:100},content:[{type:'text',text:JSON.stringify(proposal)}]}));
  setAnthropicClientForTests(fake.client);
  const device={'x-device-id':newDeviceId(),'x-install-secret':newSecret()};
  assert.equal((await api(server.base,'POST','/api/fitter/device/register',{headers:device,body:{}})).status,201);
  const interpreted=await api(server.base,'POST','/api/fitter/ai/assistant',{headers:device,body:request});
  assert.equal(interpreted.status,200,interpreted.text);assert.deepEqual(interpreted.json,proposal);
  assert.equal(fake.calls.length,1);assert.equal(fake.calls[0].model,'claude-haiku-5-5');
  assert.equal(fake.calls[0].output_config.effort,'low');
  assert.deepEqual(fake.requestOptions[0],{maxRetries:0,timeout:25000});
  assert.deepEqual(JSON.parse(fake.calls[0].messages[0].content).context,request.context);
  assert.equal(budgetState().inFlightUsd,0);
  const registration=await api(server.base,'POST','/api/fitter/account/register',{body:{email:'wire-profile@example.test',password:'Fixture-wire-password-123',displayName:'Fixture name',legalVersion:6}});
  assert.equal(registration.status,201);
  const headers={authorization:`Bearer ${registration.json.token}`};
  const baseline={displayName:'Fixture name',profession:'Spawacz',experienceYears:4,processes:['141'],qualifications:'Fixture private qualifications',stamp:'Other-device stamp',publicProfile:false};
  assert.equal((await api(server.base,'PUT','/api/fitter/account/profile',{headers,body:baseline})).status,200);
  const endpoint='/api/fitter/account/profile/assistant';
  assert.equal((await api(server.base,'POST',endpoint,{body:write})).status,401);
  assert.equal((await api(server.base,'POST',endpoint,{headers,body:{...write,role:'admin'}})).status,400);
  const saved=await api(server.base,'POST',endpoint,{headers,body:write});
  assert.equal(saved.status,200,saved.text);assert.equal(saved.json.account.experienceYears,8);
  const actual=await api(server.base,'GET','/api/fitter/account/me',{headers});
  assert.equal(actual.status,200);assert.equal(actual.json.account.role,'user');
  for(const [key,value] of Object.entries(baseline)) assert.deepEqual(actual.json.account[key],key==='experienceYears'?8:value);
  assert.equal((await api(server.base,'POST',endpoint,{headers,body:{...write,value:9}})).status,409);
  assert.equal((await api(server.base,'POST',endpoint,{headers,body:write})).status,200);
  assert.equal((await api(server.base,'GET','/api/fitter/account/reports',{headers})).status,403);
  const fieldProofs=[];
  if(process.argv.includes('--fields')) {
    const commands={add:'Dodaj w moim profilu procesy 141',remove:'Usuń w moim profilu procesy 111',replace:'Ustaw w moim profilu procesy na 111 i 141',
      qualifications:'Ustaw w moim profilu kwalifikacje na "Szkolenie TIG, grupa A."',stamp:'Ustaw w moim profilu stempel na "AB.7?"'};
    for(const [mode,command] of Object.entries(commands)) {
      const input=JSON.parse(fs.readFileSync(`build/assistant-professional-${mode}-wire.json`,'utf8'));
      const body=JSON.parse(fs.readFileSync(`build/assistant-professional-${mode}-write.json`,'utf8'));
      assert.deepEqual(input.capabilities[0].professional_profile_fields,['profession','experienceYears','processes','qualifications','stamp']);
      assert.ok(!JSON.stringify(input.context).includes('Private qualifications'));
      assert.ok(!JSON.stringify(input.context).includes('Private stamp'));
      const output={kind:'execute',steps:[{skill_id:'account.professional.edit',command}],message:''};
      const provider=fakeAnthropic(()=>({stop_reason:'end_turn',usage:{input_tokens:1500,output_tokens:100},content:[{type:'text',text:JSON.stringify(output)}]}));
      setAnthropicClientForTests(provider.client);
      const interpretation=await api(server.base,'POST','/api/fitter/ai/assistant',{headers:device,body:input});
      assert.equal(interpretation.status,200,interpretation.text);assert.deepEqual(interpretation.json,output);
      assert.equal(provider.calls.length,1);assert.equal(provider.calls[0].model,'claude-haiku-5-5');
      assert.equal(provider.calls[0].output_config.effort,'low');assert.deepEqual(provider.requestOptions[0],{maxRetries:0,timeout:25000});
      assert.deepEqual(JSON.parse(provider.calls[0].messages[0].content).context,input.context);
      const nativeBaseline={displayName:'Fixture name',profession:'Spawacz',experienceYears:4,processes:['135','111'],qualifications:'Private qualifications',stamp:'Private stamp',publicProfile:false};
      assert.equal((await api(server.base,'PUT','/api/fitter/account/profile',{headers,body:nativeBaseline})).status,200);
      const persisted=await api(server.base,'POST',endpoint,{headers,body});assert.equal(persisted.status,200,persisted.text);
      const read=await api(server.base,'GET','/api/fitter/account/me',{headers});assert.equal(read.status,200);
      for(const [field,value] of Object.entries(nativeBaseline)) assert.deepEqual(read.json.account[field],field===body.field?body.value:value);
      assert.equal(read.json.account.role,'user');
      assert.equal(budgetState().inFlightUsd,0);
      fieldProofs.push({mode,interpreterStatus:interpretation.status,writeStatus:persisted.status,readStatus:read.status,
        requestBytes:Buffer.byteLength(JSON.stringify(input)),writeBytes:Buffer.byteLength(JSON.stringify(body))});
    }
    for(const field of ['profession','qualifications','stamp','processes']) {
      const body=JSON.parse(fs.readFileSync(`build/assistant-professional-clear-${field}-write.json`,'utf8'));
      const clearBaseline={displayName:'Fixture name',profession:'Spawacz',experienceYears:4,processes:['141'],qualifications:'Private qualifications',stamp:'Private stamp',publicProfile:false};
      assert.equal((await api(server.base,'PUT','/api/fitter/account/profile',{headers,body:clearBaseline})).status,200);
      assert.equal(body.field,field);assert.deepEqual(body.value,field==='processes'?[]:'');
      const clear=await api(server.base,'POST',endpoint,{headers,body});assert.equal(clear.status,200,clear.text);
      const read=await api(server.base,'GET','/api/fitter/account/me',{headers});assert.equal(read.status,200);
      for(const [key,value] of Object.entries(clearBaseline)) assert.deepEqual(read.json.account[key],key===field?body.value:value);
      fieldProofs.push({mode:`clear-${field}`,writeStatus:clear.status,readStatus:read.status,writeBytes:Buffer.byteLength(JSON.stringify(body))});
    }
  }
  let magProof;
  if(process.argv.includes('--mag')) {
    const input=JSON.parse(fs.readFileSync('build/assistant-professional-mag-wire.json','utf8'));
    const body=JSON.parse(fs.readFileSync('build/assistant-professional-mag-write.json','utf8'));
    assert.equal(input.text,'Dodaj MAG do mojego profilu');
    assert.equal(input.capabilities[0].professional_process_questions,true);
    assert.deepEqual(body,{field:'processes',value:['135','141'],expected:['141']});
    const output={kind:'execute',steps:[{skill_id:'account.professional.edit',command:'Dodaj w moim profilu procesy MAG'}],message:''};
    const provider=fakeAnthropic(()=>({stop_reason:'end_turn',usage:{input_tokens:1500,output_tokens:100},content:[{type:'text',text:JSON.stringify(output)}]}));
    setAnthropicClientForTests(provider.client);
    const interpretation=await api(server.base,'POST','/api/fitter/ai/assistant',{headers:device,body:input});
    assert.equal(interpretation.status,200,interpretation.text);assert.deepEqual(interpretation.json,output);
    assert.equal(provider.calls.length,1);assert.equal(provider.calls[0].model,'claude-haiku-5-5');
    assert.equal(provider.calls[0].output_config.effort,'low');assert.deepEqual(provider.requestOptions[0],{maxRetries:0,timeout:25000});
    const nativeBaseline={...baseline,processes:['141']};
    assert.equal((await api(server.base,'PUT','/api/fitter/account/profile',{headers,body:nativeBaseline})).status,200);
    const persisted=await api(server.base,'POST',endpoint,{headers,body});assert.equal(persisted.status,200,persisted.text);
    const read=await api(server.base,'GET','/api/fitter/account/me',{headers});assert.equal(read.status,200);
    for(const [field,value] of Object.entries(nativeBaseline)) assert.deepEqual(read.json.account[field],field==='processes'?body.value:value);
    assert.equal(read.json.account.role,'user');assert.equal(budgetState().inFlightUsd,0);
    magProof={interpreterStatus:interpretation.status,writeStatus:persisted.status,readStatus:read.status,
      requestBytes:Buffer.byteLength(JSON.stringify(input)),writeBytes:Buffer.byteLength(JSON.stringify(body)),
      providerCalls:provider.calls.length,reply:'native choice 135; captured confirmed write'};
  }
  const proof={checkedAt:new Date().toISOString(),backendHead:execFileSync('git',['rev-parse','HEAD'],{cwd:backend,encoding:'utf8'}).trim(),
    interpreterStatus:interpreted.status,writeStatus:saved.status,readbackStatus:actual.status,conflictStatus:409,retryStatus:200,anonymousStatus:401,injectedRoleStatus:400,reportsStatus:403,
    requestBytes:Buffer.byteLength(JSON.stringify(request)),writeBytes:Buffer.byteLength(JSON.stringify(write)),fieldProofs,magProof,provider:'injected fake; zero paid calls',target:'local Express/SQLite; no production changes'};
  fs.writeFileSync('build/professional-profile-wire-proof.json',JSON.stringify(proof,null,2));
  console.log(JSON.stringify(proof));
} finally {await server.close();}
