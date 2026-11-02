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
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class Release0524AssistantOfflineTest extends Release0524SmokeTest {
 @Test public void offlineAssistantOpensAndCalculatesPipeSlope() throws Exception {
  directory=new File(context.getExternalFilesDir(null),"release-smoke");
  assertTrue(directory.mkdirs() || directory.isDirectory());
  try {
   assertTrue("Disposable emulator only", android.os.Build.MODEL.startsWith("sdk_gphone"));
   ApplicationInfo app=context.getPackageManager().getApplicationInfo(APP,0);
   assertEquals(0,app.flags & ApplicationInfo.FLAG_DEBUGGABLE);
   String sha=apkSha(app.sourceDir); assertEquals(EXPECTED_SHA,sha);
   report.put("installedApkSha256",sha);
   assertEquals("0.5.24",context.getPackageManager().getPackageInfo(APP,0).versionName);
   assertTrue(context.getSharedPreferences("FlutterSharedPreferences",Context.MODE_PRIVATE).getAll().isEmpty());
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
   set(waitNode(n->n.isEditable() && text(n).contains("Co mam zrobić")),"oblicz spadek rury");
   click(waitNode(n->text(n).contains("Wykonaj") && !n.isEditable()));
   waitNode(n->text(n).contains("Spadek rury"));
   set(waitNode(n->n.isEditable() && text(n).contains("Co mam zrobić")),"spadek 1% na 6 metrow");
   click(waitNode(n->text(n).contains("Wykonaj") && !n.isEditable()));
   waitNode(n->text(n).contains("60.0") || text(n).contains("60,0"));
   assertNull(manager.getActiveNetwork());
   report.put("offlineAssistantOpenedSlope",true);report.put("displayedRiseMm",60);
   Bitmap screenshot=ui.takeScreenshot();assertNotNull(screenshot);
   try(FileOutputStream out=new FileOutputStream(new File(directory,"assistant-slope.png"))){assertTrue(screenshot.compress(Bitmap.CompressFormat.PNG,100,out));}
   dump();
  } finally {
   try {shell("am force-stop "+APP);}
   finally {
    if(networkChanged){shell("cmd connectivity airplane-mode disable");shell("svc wifi enable");shell("svc data enable");}
    report.put("serverFixtureCreated",false);emit();
   }
  }
 }
}
