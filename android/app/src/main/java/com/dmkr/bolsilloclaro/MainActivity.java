package com.dmkr.bolsilloclaro;

import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.NumberFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends android.app.Activity {
    private static final String PREFS = "bolsillo_claro";
    private static final double MONTHLY_INCOME = 1850;
    private static final double MONTHLY_BUDGET = 1200;
    private static final String[] CATEGORIES = {"Casa", "Comida", "Transporte"};

    private final ArrayList<Movement> movements = new ArrayList<>();
    private SharedPreferences prefs;
    private boolean darkMode;
    private int background;
    private int surface;
    private int text;
    private int muted;
    private int accent;
    private int positive;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        darkMode = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        configureColors();
        loadMovements();
        showDashboard();
    }

    private void configureColors() {
        background = Color.parseColor(darkMode ? "#101412" : "#F3F6F4");
        surface = Color.parseColor(darkMode ? "#18211D" : "#FFFFFF");
        text = Color.parseColor(darkMode ? "#F2F7F4" : "#111916");
        muted = Color.parseColor(darkMode ? "#9BA8A1" : "#68746E");
        accent = Color.parseColor("#0A7448");
        positive = Color.parseColor("#0E9D61");
    }

    private void showDashboard() {
        FrameLayout frame = new FrameLayout(this);
        frame.setBackgroundColor(background);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(false);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(34), dp(20), dp(96));
        scroll.addView(root);
        frame.addView(scroll);

        root.addView(header());
        root.addView(balanceCard());
        root.addView(spendingCard());
        root.addView(categoryRow());
        root.addView(sectionTitle("Movimientos"));
        for (int i = 0; i < Math.min(5, movements.size()); i++) {
            root.addView(movementRow(movements.get(i)));
        }

        Button add = new Button(this);
        add.setText("Anadir");
        add.setTextColor(Color.WHITE);
        add.setTextSize(16);
        add.setTypeface(Typeface.DEFAULT_BOLD);
        add.setAllCaps(false);
        add.setBackground(rounded(accent, 100));
        add.setOnClickListener(v -> showAddDialog());
        FrameLayout.LayoutParams addLp = new FrameLayout.LayoutParams(dp(128), dp(54), Gravity.BOTTOM | Gravity.RIGHT);
        addLp.setMargins(0, 0, dp(20), dp(22));
        frame.addView(add, addLp);

        setContentView(frame);
    }

    private View header() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, 0, 0, dp(18));

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        TextView title = label("Bolsillo Claro", 30, text, true);
        TextView month = label(new SimpleDateFormat("MMMM yyyy", new Locale("es", "ES")).format(new Date()), 15, muted, false);
        copy.addView(title);
        copy.addView(month);
        row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));

        TextView icon = label("$", 22, accent, true);
        icon.setGravity(Gravity.CENTER);
        icon.setBackground(rounded(surface, 14));
        row.addView(icon, new LinearLayout.LayoutParams(dp(46), dp(46)));
        return row;
    }

    private View balanceCard() {
        LinearLayout card = card();
        card.addView(label("Saldo disponible", 15, muted, true));
        TextView amount = label(currency(available()), 40, positive, true);
        amount.setPadding(0, dp(8), 0, dp(8));
        card.addView(amount);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.addView(label("Ingresos", 14, muted, false), new LinearLayout.LayoutParams(0, -2, 1));
        row.addView(label(currency(MONTHLY_INCOME), 14, muted, true));
        card.addView(row);
        return withMargins(card, 0, 0, 0, 14);
    }

    private View spendingCard() {
        LinearLayout card = card();
        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.addView(label("Gasto del mes", 17, text, true), new LinearLayout.LayoutParams(0, -2, 1));
        top.addView(label(currency(spent()), 16, text, true));
        card.addView(top);

        ProgressBar bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(100);
        bar.setProgress((int) Math.round(Math.min(spent() / MONTHLY_BUDGET, 1) * 100));
        card.addView(withMargins(bar, 0, 14, 0, 10), new LinearLayout.LayoutParams(-1, dp(12)));
        card.addView(label("Presupuesto " + currency(MONTHLY_BUDGET), 13, muted, false));
        return withMargins(card, 0, 0, 0, 14);
    }

    private View categoryRow() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER);
        for (String category : CATEGORIES) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(12), dp(12), dp(12));
            card.setBackground(rounded(surface, 8));
            card.addView(label(iconFor(category), 18, accent, true));
            card.addView(label(category, 13, text, true));
            card.addView(label(currency(totalFor(category)), 12, muted, false));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(104), 1);
            lp.setMargins(dp(4), 0, dp(4), dp(14));
            row.addView(card, lp);
        }
        return row;
    }

    private TextView sectionTitle(String value) {
        TextView title = label(value, 20, text, true);
        title.setPadding(0, dp(6), 0, dp(10));
        return title;
    }

    private View movementRow(Movement item) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(12), dp(12), dp(12), dp(12));
        row.setBackground(rounded(surface, 8));

        TextView icon = label(item.category.substring(0, 1), 16, accent, true);
        icon.setGravity(Gravity.CENTER);
        icon.setBackground(rounded(withAlpha(accent, 28), 8));
        row.addView(icon, new LinearLayout.LayoutParams(dp(42), dp(42)));

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(dp(12), 0, 0, 0);
        copy.addView(label(item.title, 16, text, true));
        copy.addView(label(item.category, 13, muted, false));
        row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));

        row.addView(label(currency(item.amount), 15, text, true));
        return withMargins(row, 0, 0, 0, 10);
    }

    private LinearLayout card() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(18), dp(18), dp(18), dp(18));
        card.setBackground(rounded(surface, 8));
        return card;
    }

    private void showAddDialog() {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(10), dp(20), 0);

        EditText titleInput = new EditText(this);
        titleInput.setHint("Nombre");
        form.addView(titleInput);

        EditText amountInput = new EditText(this);
        amountInput.setHint("Importe");
        amountInput.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        form.addView(amountInput);

        Spinner categoryInput = new Spinner(this);
        categoryInput.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, CATEGORIES));
        final String[] selected = {"Comida"};
        categoryInput.setSelection(1);
        categoryInput.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                selected[0] = CATEGORIES[position];
            }
            @Override public void onNothingSelected(AdapterView<?> parent) { }
        });
        form.addView(categoryInput);

        new AlertDialog.Builder(this)
            .setTitle("Anadir gasto")
            .setView(form)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Guardar", (dialog, which) -> {
                double amount = parseAmount(amountInput.getText().toString());
                String title = titleInput.getText().toString().trim();
                if (!title.isEmpty() && amount > 0) {
                    movements.add(0, new Movement(title, selected[0], -amount));
                    saveMovements();
                    showDashboard();
                }
            })
            .show();
    }

    private void loadMovements() {
        movements.clear();
        String raw = prefs.getString("movements", "");
        if (!raw.isEmpty()) {
            try {
                JSONArray array = new JSONArray(raw);
                for (int i = 0; i < array.length(); i++) {
                    JSONObject item = array.getJSONObject(i);
                    movements.add(new Movement(item.getString("title"), item.getString("category"), item.getDouble("amount")));
                }
                return;
            } catch (Exception ignored) {
                movements.clear();
            }
        }
        movements.add(new Movement("Supermercado", "Comida", -46.20));
        movements.add(new Movement("Metro", "Transporte", -12.80));
        movements.add(new Movement("Alquiler", "Casa", -620));
    }

    private void saveMovements() {
        JSONArray array = new JSONArray();
        try {
            for (Movement movement : movements) {
                JSONObject item = new JSONObject();
                item.put("title", movement.title);
                item.put("category", movement.category);
                item.put("amount", movement.amount);
                array.put(item);
            }
        } catch (Exception ignored) { }
        prefs.edit().putString("movements", array.toString()).apply();
    }

    private double spent() {
        double total = 0;
        for (Movement movement : movements) {
            if (movement.amount < 0) total += Math.abs(movement.amount);
        }
        return total;
    }

    private double available() {
        return MONTHLY_INCOME - spent();
    }

    private double totalFor(String category) {
        double total = 0;
        for (Movement movement : movements) {
            if (movement.category.equals(category) && movement.amount < 0) total += Math.abs(movement.amount);
        }
        return total;
    }

    private double parseAmount(String value) {
        try {
            return Double.parseDouble(value.replace(",", "."));
        } catch (Exception e) {
            return 0;
        }
    }

    private String currency(double value) {
        NumberFormat format = NumberFormat.getCurrencyInstance(new Locale("es", "ES"));
        return format.format(value);
    }

    private String iconFor(String category) {
        if ("Casa".equals(category)) return "H";
        if ("Comida".equals(category)) return "C";
        return "T";
    }

    private TextView label(String value, int sp, int color, boolean bold) {
        TextView label = new TextView(this);
        label.setText(value);
        label.setTextSize(sp);
        label.setTextColor(color);
        label.setIncludeFontPadding(true);
        if (bold) label.setTypeface(Typeface.DEFAULT_BOLD);
        return label;
    }

    private View withMargins(View view, int left, int top, int right, int bottom) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(dp(left), dp(top), dp(right), dp(bottom));
        view.setLayoutParams(lp);
        return view;
    }

    private GradientDrawable rounded(int color, int radius) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(radius));
        return drawable;
    }

    private int withAlpha(int color, int alpha) {
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private static final class Movement {
        final String title;
        final String category;
        final double amount;

        Movement(String title, String category, double amount) {
            this.title = title;
            this.category = category;
            this.amount = amount;
        }
    }
}
