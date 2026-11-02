package com.startklaar.fitterwelder.releaseqa;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.graphics.Bitmap;
import android.net.ConnectivityManager;
import android.os.SystemClock;
import androidx.test.runner.AndroidJUnit4;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.List;
import java.util.UUID;
import android.view.accessibility.AccessibilityNodeInfo;
import org.json.JSONObject;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class Release0527KnowledgeRetryTest extends Release0527SmokeTest {
 AccessibilityNodeInfo assistantInput() throws Exception {
  long until=SystemClock.uptimeMillis()+25000;
  do {
   List<AccessibilityNodeInfo> fields=edits();
   if(fields.size()>=2)return fields.get(fields.size()-1);
   SystemClock.sleep(150);
  } while(SystemClock.uptimeMillis()<until);
  dump();throw new AssertionError("Assistant text field not found");
 }
 @Test public void offlineKnowledgeRetryRemainsAvailable() throws Exception {
  directory=new File(context.getExternalFilesDir(null),"release-smoke");
  assertTrue(directory.mkdirs() || directory.isDirectory());
  try {
   assertTrue("Disposable emulator only", android.os.Build.MODEL.startsWith("sdk_gphone"));
   ApplicationInfo app=context.getPackageManager().getApplicationInfo(APP,0);
   assertEquals(0,app.flags & ApplicationInfo.FLAG_DEBUGGABLE);
   String sha=apkSha(app.sourceDir); assertEquals(EXPECTED_SHA,sha);
   report.put("installedApkSha256",sha);
   assertEquals("0.5.27",context.getPackageManager().getPackageInfo(APP,0).versionName);
   android.content.SharedPreferences prefs=context.getSharedPreferences("FlutterSharedPreferences",Context.MODE_PRIVATE);
   assertTrue(prefs.getAll().isEmpty());
   device=UUID.randomUUID().toString().replace("-","");byte[] bytes=new byte[32];new SecureRandom().nextBytes(bytes);secret=hex(bytes);
   recovery=new File(directory,"fixture.private.json");
   try(FileOutputStream out=new FileOutputStream(recovery)){out.write(new JSONObject().put("deviceId",device).put("installSecret",secret).toString().getBytes(StandardCharsets.UTF_8));}
   assertTrue(prefs.edit().putString("flutter.fitter_device_id",device).putString("flutter.fitter_install_secret",secret).putString("flutter.legal_consent_v1", "{\"version\":6,\"acceptedAt\":\"2026-11-02T00:00:00.000Z\"}").commit());ownsFixture=true;
   AccessibilityServiceInfo info=ui.getServiceInfo();
   info.flags|=AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS|AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;ui.setServiceInfo(info);
   networkChanged=true;
   shell("cmd connectivity airplane-mode enable");shell("svc wifi disable");shell("svc data disable");
   ConnectivityManager manager=(ConnectivityManager)context.getSystemService(Context.CONNECTIVITY_SERVICE);
   long until=SystemClock.uptimeMillis()+10000;
   while(manager.getActiveNetwork()!=null && SystemClock.uptimeMillis()<until)SystemClock.sleep(200);
   assertNull(manager.getActiveNetwork()); report.put("offlineBeforeLaunch",true);
   Intent launch=context.getPackageManager().getLaunchIntentForPackage(APP);assertNotNull(launch);
   launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);context.startActivity(launch);
   click(waitNode(n->text(n).contains("Powiedz, co zrobić")));
   set(assistantInput(),"dlaczego powstaja pory w spoinie");
   click(waitNode(n->text(n).contains("Wykonaj") && !n.isEditable()));
   waitNode(n->text(n).contains("Tryb offline"));
   waitNode(n->text(n).contains("Nie znalazłem tego w pomocy offline"));
   for(AccessibilityNodeInfo n:nodes()) assertFalse(text(n).contains("spoin z importu"));
   SystemClock.sleep(8000);
   waitNode(n->text(n).contains("Ponów pytanie"));
   set(assistantInput(),"nowy szkic");
   click(waitNode(n->text(n).contains("Ponów pytanie")));
   SystemClock.sleep(2500);
   waitNode(n->n.isEditable() && "nowy szkic".equals(String.valueOf(n.getText())));
   waitNode(n->text(n).contains("Ponów pytanie"));
   assertNull(manager.getActiveNetwork());
   report.put("offlineRetryVisibleAfterNotification",true);report.put("draftPreserved",true);
   Bitmap screenshot=ui.takeScreenshot();assertNotNull(screenshot);
   try(FileOutputStream out=new FileOutputStream(new File(directory,"assistant-retry.png"))){assertTrue(screenshot.compress(Bitmap.CompressFormat.PNG,100,out));}
   dump();
  } finally {
   try {cleanup();} finally {emit();}
  }
 }
}
