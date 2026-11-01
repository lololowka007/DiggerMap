package app.diggermap.route;

import android.app.*; import android.os.*; import android.content.*; import android.graphics.*; import android.graphics.drawable.*; import android.hardware.*; import android.speech.*; import android.view.*; import android.widget.*; import java.util.*;

public class MainActivity extends Activity implements SensorEventListener {
  LinearLayout root, blocks; TextView action, mapInfo; SensorManager sensors; float still=0; boolean listening=false;
  int mint=Color.rgb(102,240,184), bg=Color.rgb(9,19,27), panel=Color.rgb(19,33,41);
  public void onCreate(Bundle b){super.onCreate(b); getWindow().setStatusBarColor(bg); build(); sensors=(SensorManager)getSystemService(SENSOR_SERVICE);}
  TextView t(String s,int z){ TextView v=new TextView(this); v.setText(s); v.setTextColor(Color.WHITE); v.setTextSize(z); v.setPadding(18,12,18,12); return v; }
  GradientDrawable box(){ GradientDrawable d=new GradientDrawable(); d.setColor(panel); d.setCornerRadius(24); return d; }
  void build(){ root=new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setPadding(16,12,16,12); root.setBackgroundColor(bg); ScrollView scroll=new ScrollView(this); blocks=new LinearLayout(this); blocks.setOrientation(LinearLayout.VERTICAL); blocks.setPadding(0,0,0,90);
    TextView head=t("DIGGERMAP\nКарта маршрута",24); head.setTextColor(mint); blocks.addView(head,new LinearLayout.LayoutParams(-1,-2));
    TextView stats=t("ПРОЙДЕНО   0,0 м        НАПРАВЛЕНИЕ   0°\nУРОВЕНЬ ВХОДА",16); stats.setBackground(box()); blocks.addView(stats,new LinearLayout.LayoutParams(-1,80));
    mapInfo=t("ВХОД\n\n        ● Вы здесь\n\nКарта растягивается под экран устройства",17); mapInfo.setGravity(Gravity.CENTER); mapInfo.setBackground(box()); LinearLayout.LayoutParams mp=new LinearLayout.LayoutParams(-1,0,1); mp.setMargins(0,12,0,12); blocks.addView(mapInfo,mp);
    action=t("Готов. Скажи: «иду прямо 10 метров», «тупик», «разворачиваюсь назад», «опасность впереди».",15); action.setBackground(box()); blocks.addView(action,new LinearLayout.LayoutParams(-1,110));
    scroll.addView(blocks); root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
    LinearLayout bar=new LinearLayout(this); bar.setGravity(Gravity.CENTER); String[] names={"Журнал","Метки","Вид","🎙"}; for(String n:names){Button x=new Button(this); x.setText(n); x.setOnClickListener(v->click(n)); bar.addView(x,new LinearLayout.LayoutParams(0,58,1));} root.addView(bar); setContentView(root);
  }
  void click(String n){ if(n.equals("Вид")){ editMode(); return; } if(n.equals("Метки")){ action.setText("Метки: поиск, фото, опасности, стрелки и тупики."); return; } if(n.equals("Журнал")){ action.setText("Журнал экспедиции пока пуст."); return; } if(!listening){ requestPermissions(new String[]{"android.permission.RECORD_AUDIO"},4); Intent i=new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH); i.putExtra(RecognizerIntent.EXTRA_LANGUAGE,"ru-RU"); i.putExtra(RecognizerIntent.EXTRA_PROMPT,"Говори команду"); startActivityForResult(i,5); listening=true; } }
  void editMode(){ action.setText("РЕЖИМ НАСТРОЙКИ: удерживай блок и перетаскивай его. Кнопки блоков адаптивны."); for(int i=0;i<blocks.getChildCount();i++){View v=blocks.getChildAt(i); v.setOnLongClickListener(x->{v.setAlpha(.65f); action.setText("Блок выбран. Перетащи его выше или ниже."); return true;});} }
  protected void onActivityResult(int r,int c,Intent d){super.onActivityResult(r,c,d); listening=false; if(r==5&&d!=null){ArrayList<String> a=d.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS); if(a!=null&&!a.isEmpty()){String s=a.get(0); action.setText("Услышал: «"+s+"»\nКоманда сохранена в журнал."); ((android.os.Vibrator)getSystemService(VIBRATOR_SERVICE)).vibrate(80);}}}
  public void onSensorChanged(SensorEvent e){} public void onAccuracyChanged(Sensor s,int a){}
}
