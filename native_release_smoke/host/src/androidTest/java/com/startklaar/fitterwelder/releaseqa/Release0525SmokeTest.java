package com.startklaar.fitterwelder.releaseqa;

import android.app.Instrumentation;
import android.app.UiAutomation;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.graphics.Bitmap;
import android.graphics.Rect;
import android.net.ConnectivityManager;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.util.Base64;
import android.util.Log;
import android.view.InputDevice;
import android.view.MotionEvent;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityWindowInfo;
import android.view.accessibility.AccessibilityNodeInfo;
import android.accessibilityservice.AccessibilityServiceInfo;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.runner.AndroidJUnit4;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.json.JSONObject;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.*;
import java.util.function.Predicate;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class Release0525SmokeTest {
 static final String APP="com.startklaar.fitterwelder";
 static final String EXPECTED_SHA="00ec065fc7056260399c2b15bf85231ee5326667b2f33ed2430b8abbcfdf480d";
 final Instrumentation instrumentation=InstrumentationRegistry.getInstrumentation();
 final Context context=instrumentation.getTargetContext();
 final UiAutomation ui=instrumentation.getUiAutomation();
 final JSONObject report=new JSONObject();
 File directory, recovery;
 String device, secret;
 boolean ownsFixture=false;
 boolean networkChanged=false;

 String shell(String command) throws Exception {
  try(ParcelFileDescriptor fd=ui.executeShellCommand(command);
      InputStream in=new ParcelFileDescriptor.AutoCloseInputStream(fd)) {
   return new String(in.readAllBytes(),StandardCharsets.UTF_8).trim();
  }
 }
 List<AccessibilityNodeInfo> nodes() {
  List<AccessibilityNodeInfo> result=new ArrayList<>();
  collect(ui.getRootInActiveWindow(),result);return result;
 }
 void collect(AccessibilityNodeInfo node,List<AccessibilityNodeInfo> result) {
  if(node==null)return;result.add(node);
  for(int i=0;i<node.getChildCount();i++)collect(node.getChild(i),result);
 }
 String text(AccessibilityNodeInfo node) {
  return String.valueOf(node.getText())+"\n"+String.valueOf(node.getContentDescription());
 }
 AccessibilityNodeInfo waitNode(Predicate<AccessibilityNodeInfo> predicate) throws Exception {
  long until=SystemClock.uptimeMillis()+25000;
  do {
   for(AccessibilityNodeInfo n:nodes()) if(n.isVisibleToUser() && predicate.test(n)) return n;
   SystemClock.sleep(150);
  } while(SystemClock.uptimeMillis()<until);
  dump();throw new AssertionError("Expected native accessibility node not found; inspect UI dump");
 }
 void click(AccessibilityNodeInfo node) {
  if(node.performAction(AccessibilityNodeInfo.ACTION_CLICK))return;
  Rect bounds=new Rect();node.getBoundsInScreen(bounds);
  long time=SystemClock.uptimeMillis();
  MotionEvent down=MotionEvent.obtain(time,time,MotionEvent.ACTION_DOWN,bounds.exactCenterX(),bounds.exactCenterY(),0);
  MotionEvent up=MotionEvent.obtain(time,time+80,MotionEvent.ACTION_UP,bounds.exactCenterX(),bounds.exactCenterY(),0);
  down.setSource(InputDevice.SOURCE_TOUCHSCREEN);up.setSource(InputDevice.SOURCE_TOUCHSCREEN);
  ui.injectInputEvent(down,true);ui.injectInputEvent(up,true);down.recycle();up.recycle();
 }
 void set(AccessibilityNodeInfo node,String value) throws Exception {
  click(node);SystemClock.sleep(300);
  instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_MOVE_END);
  for(int i=0;i<32;i++)instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_DEL);
  instrumentation.sendStringSync(value);SystemClock.sleep(500);
  boolean entered=false;
  for(AccessibilityNodeInfo field:edits()) {
   if(field.isFocused() && value.equals(String.valueOf(field.getText())))entered=true;
  }
  if(!entered)dump();
  assertTrue("Focused native field must contain exactly requested value",entered);
  for(AccessibilityWindowInfo window:ui.getWindows()) {
   if(window.getType()==AccessibilityWindowInfo.TYPE_INPUT_METHOD) {
    instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);SystemClock.sleep(300);break;
   }
  }
 }
 List<AccessibilityNodeInfo> edits() {
  List<AccessibilityNodeInfo> fields=new ArrayList<>();
  for(AccessibilityNodeInfo n:nodes()) if(n.isVisibleToUser() && n.isEditable())fields.add(n);
  fields.sort(Comparator.comparingInt((AccessibilityNodeInfo n)->{Rect b=new Rect();n.getBoundsInScreen(b);return b.top;})
   .thenComparingInt(n->{Rect b=new Rect();n.getBoundsInScreen(b);return b.left;}));
  return fields;
 }
 void dump() throws Exception {
  StringBuilder data=new StringBuilder();
  for(AccessibilityNodeInfo n:nodes())data.append(n.getClassName()).append(" | ").append(text(n)).append(" | editable=").append(n.isEditable()).append('\n');
  try(FileOutputStream out=new FileOutputStream(new File(directory,"native-ui.txt"))) {out.write(data.toString().getBytes(StandardCharsets.UTF_8));}
 }
 String hex(byte[] bytes) {StringBuilder s=new StringBuilder();for(byte b:bytes)s.append(String.format("%02x",b&255));return s.toString();}
 String apkSha(String path) throws Exception {
  MessageDigest digest=MessageDigest.getInstance("SHA-256");
  try(InputStream in=new FileInputStream(path)){byte[] buffer=new byte[65536];int n;while((n=in.read(buffer))!=-1)digest.update(buffer,0,n);}
  return hex(digest.digest());
 }
 void restoreNetwork() throws Exception {
  shell("cmd connectivity airplane-mode disable");shell("svc wifi enable");shell("svc data enable");
  ConnectivityManager manager=(ConnectivityManager)context.getSystemService(Context.CONNECTIVITY_SERVICE);
  long until=SystemClock.uptimeMillis()+20000;
  while(manager.getActiveNetwork()==null && SystemClock.uptimeMillis()<until)SystemClock.sleep(250);
 }
 void cleanup() throws Exception {
  if(networkChanged)restoreNetwork();
  if(!ownsFixture)return;
  HttpURLConnection connection=(HttpURLConnection)new URL("https://fitter-welder-pro-backend-production.up.railway.app/api/fitter/me").openConnection();
  connection.setRequestMethod("DELETE");connection.setConnectTimeout(15000);connection.setReadTimeout(15000);
  connection.setRequestProperty("x-device-id",device);connection.setRequestProperty("x-install-secret",secret);
  int status=connection.getResponseCode();report.put("cleanupStatus",status);
  try(InputStream in=status>=400?connection.getErrorStream():connection.getInputStream()) {
   boolean ok=new JSONObject(new String(in.readAllBytes(),StandardCharsets.UTF_8)).optBoolean("ok");
   report.put("cleanupOk",ok);assertEquals(200,status);assertTrue(ok);
  } finally {connection.disconnect();}
  assertTrue(recovery.delete());report.put("privateFixtureRemoved",true);
 }
 void emit() throws Exception {
  try(FileOutputStream out=new FileOutputStream(new File(directory,"report.json"))){out.write(report.toString(2).getBytes(StandardCharsets.UTF_8));}
  String encoded=Base64.encodeToString(report.toString().getBytes(StandardCharsets.UTF_8),Base64.NO_WRAP);
  int count=(encoded.length()+899)/900;
  for(int i=0;i<count;i++)Log.i("FWP_RELEASE_QA","FWP_RELEASE_SMOKE_REPORT "+i+"/"+count+": "+encoded.substring(i*900,Math.min((i+1)*900,encoded.length())));
 }
 @Test public void exactSignedRelease0525LooksUpDn50AndCalculatesOffline() throws Exception {
  directory=new File(context.getExternalFilesDir(null),"release-smoke");assertTrue(directory.mkdirs()||directory.isDirectory());
  try {
   assertTrue("Disposable emulator only",android.os.Build.MODEL.startsWith("sdk_gphone"));
   report.put("model",android.os.Build.MODEL);
   ApplicationInfo app=context.getPackageManager().getApplicationInfo(APP,0);
   assertEquals(0,app.flags & ApplicationInfo.FLAG_DEBUGGABLE);
   String sha=apkSha(app.sourceDir);assertEquals(EXPECTED_SHA,sha);report.put("installedApkSha256",sha);
   report.put("version",context.getPackageManager().getPackageInfo(APP,0).versionName);
   assertEquals("0.5.25",report.getString("version"));
   SharedPreferences prefs=context.getSharedPreferences("FlutterSharedPreferences",Context.MODE_PRIVATE);
   assertTrue("Fresh installation only",prefs.getAll().isEmpty());
   device=UUID.randomUUID().toString().replace("-","");byte[] bytes=new byte[32];new SecureRandom().nextBytes(bytes);secret=hex(bytes);
   recovery=new File(directory,"fixture.private.json");
   try(FileOutputStream out=new FileOutputStream(recovery)){out.write(new JSONObject().put("deviceId",device).put("installSecret",secret).toString().getBytes(StandardCharsets.UTF_8));}
   assertTrue(prefs.edit().putString("flutter.fitter_device_id",device).putString("flutter.fitter_install_secret",secret).commit());ownsFixture=true;
   AccessibilityServiceInfo info=ui.getServiceInfo();info.flags|=AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS|AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;ui.setServiceInfo(info);
   networkChanged=true;
   shell("cmd connectivity airplane-mode enable");shell("svc wifi disable");shell("svc data disable");
   ConnectivityManager manager=(ConnectivityManager)context.getSystemService(Context.CONNECTIVITY_SERVICE);
   long until=SystemClock.uptimeMillis()+10000;
   while(manager.getActiveNetwork()!=null && SystemClock.uptimeMillis()<until)SystemClock.sleep(200);
   assertNull("Offline calculation must have no active network",manager.getActiveNetwork());report.put("offlineBeforeLaunch",true);
   Intent launch=context.getPackageManager().getLaunchIntentForPackage(APP);assertNotNull(launch);launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);context.startActivity(launch);
   AccessibilityNodeInfo search=waitNode(AccessibilityNodeInfo::isEditable);set(search,"DN50");
   click(waitNode(n->text(n).contains("DN ↔ mm") && !n.isEditable()));
   waitNode(n->text(n).contains("DN-MM"));
   waitNode(n->n.isEditable() && "50".equals(String.valueOf(n.getText())));
   waitNode(n->text(n).contains("60.3"));
   assertNull(manager.getActiveNetwork());
   Bitmap dnScreenshot=ui.takeScreenshot();assertNotNull(dnScreenshot);
   try(FileOutputStream out=new FileOutputStream(new File(directory,"release-dn50.png"))){assertTrue(dnScreenshot.compress(Bitmap.CompressFormat.PNG,100,out));}
   report.put("dn50LookupPassed",true);report.put("selectedDn",50);
   instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);SystemClock.sleep(500);
   search=waitNode(AccessibilityNodeInfo::isEditable);set(search,"ciezar rury");
   click(waitNode(n->text(n).contains("Ciężar rury") && !n.isEditable()));
   long fieldsUntil=SystemClock.uptimeMillis()+25000;
   while(edits().size()!=4 && SystemClock.uptimeMillis()<fieldsUntil)SystemClock.sleep(150);
   if(edits().size()!=4)dump();
   assertEquals("Expected exactly four calculator inputs",4,edits().size());
   String[] values={"60.3","3.91","1000","2"};
   for(int i=0;i<4;i++){List<AccessibilityNodeInfo> fields=edits();assertEquals(4,fields.size());set(fields.get(i),values[i]);}
   waitNode(n->text(n).contains("11.08 kg"));
   assertNotNull(waitNode(n->text(n).contains("5.541 kg/m")));
   assertNull(manager.getActiveNetwork());report.put("offlineNativeResultDisplayed",true);
   report.put("massPerMetre","5.541 kg/m");report.put("totalMass","11.08 kg");
   Bitmap screenshot=ui.takeScreenshot();assertNotNull(screenshot);
   try(FileOutputStream out=new FileOutputStream(new File(directory,"release-calculator.png"))){assertTrue(screenshot.compress(Bitmap.CompressFormat.PNG,100,out));}
   dump();report.put("nativeUiPassed",true);SystemClock.sleep(2000);
  } finally {
   try {cleanup();} finally {emit();}
  }
 }
}
