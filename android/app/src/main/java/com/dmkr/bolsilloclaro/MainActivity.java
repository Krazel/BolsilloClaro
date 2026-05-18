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
import android.widget.HorizontalScrollView;
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
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;
import java.util.UUID;

public class MainActivity extends android.app.Activity {
    private static final String PREFS = "bolsillo_claro";
    private static final String[] DEFAULT_CATEGORIES = {"Casa", "Comida", "Transporte"};
    private static final String[] MODES = {"Sistema", "Claro", "Oscuro"};
    private static final String[] KINDS = {"Gasto", "Ingreso"};

    private final ArrayList<Movement> movements = new ArrayList<>();
    private final ArrayList<String> categories = new ArrayList<>();
    private final ArrayList<FrequentExpense> frequentExpenses = new ArrayList<>();
    private SharedPreferences prefs;
    private double monthlyIncome = 1850;
    private double monthlyBudget = 1200;
    private int appearanceMode = 0;
    private int currentTab = 0;
    private boolean darkMode;
    private int background;
    private int surface;
    private int text;
    private int muted;
    private int accent;
    private int positive;
    private int danger;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        loadSettings();
        loadCategories();
        loadFrequentExpenses();
        loadMovements();
        configureColors();
        showDashboard();
    }

    private void configureColors() {
        boolean systemDark = (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES;
        darkMode = appearanceMode == 2 || (appearanceMode == 0 && systemDark);
        background = Color.parseColor(darkMode ? "#101412" : "#F3F6F4");
        surface = Color.parseColor(darkMode ? "#18211D" : "#FFFFFF");
        text = Color.parseColor(darkMode ? "#F2F7F4" : "#111916");
        muted = Color.parseColor(darkMode ? "#9BA8A1" : "#68746E");
        accent = Color.parseColor("#0A7448");
        positive = Color.parseColor("#0E9D61");
        danger = Color.parseColor("#C73D35");
    }

    private void showDashboard() {
        FrameLayout frame = new FrameLayout(this);
        frame.setBackgroundColor(background);

        ScrollView scroll = new ScrollView(this);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(20), dp(34), dp(20), dp(96));
        scroll.addView(root);
        frame.addView(scroll);

        if (currentTab == 0) {
            root.addView(header());
            root.addView(balanceCard());
            root.addView(spendingCard());
            root.addView(actionRow());
            root.addView(categoryScroller());
            addMovements(root, 5);
        } else if (currentTab == 1) {
            root.addView(pageHeader("Analisis", "Resumen del mes"));
            addInsights(root);
        } else if (currentTab == 2) {
            root.addView(pageHeader("Movimientos", "Busca, edita y revisa cada apunte."));
            Button addMovement = actionButton("Anadir movimiento", v -> showMovementDialog(null));
            root.addView(withMargins(addMovement, 0, 0, 0, 14), new LinearLayout.LayoutParams(-1, dp(48)));
            addFrequentPanel(root);
            addMovements(root, movements.size());
        } else if (currentTab == 3) {
            root.addView(pageHeader("Categorias", "Organiza tus gastos por grupos."));
            addCategoriesPage(root);
        } else {
            root.addView(pageHeader("Ajustes", "Presupuesto, ingresos y apariencia."));
            addSettingsPage(root);
        }

        frame.addView(bottomNav(), new FrameLayout.LayoutParams(-1, dp(70), Gravity.BOTTOM));

        setContentView(frame);
    }

    private void addMovements(LinearLayout root, int limit) {
        root.addView(sectionTitle("Movimientos"));
        if (movements.isEmpty()) {
            TextView empty = label("Anade un gasto o ingreso para empezar.", 15, muted, false);
            empty.setGravity(Gravity.CENTER);
            empty.setBackground(rounded(surface, 8));
            root.addView(withMargins(empty, 0, 0, 0, 10), new LinearLayout.LayoutParams(-1, dp(88)));
            return;
        }
        for (int i = 0; i < Math.min(limit, movements.size()); i++) {
            root.addView(movementRow(movements.get(i)));
        }
    }

    private View pageHeader(String title, String subtitle) {
        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(0, 0, 0, dp(18));
        copy.addView(label(title, 30, text, true));
        copy.addView(label(subtitle, 15, muted, false));
        return copy;
    }

    private View header() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(0, 0, 0, dp(18));

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.addView(label("Bolsillo Claro", 30, text, true));
        copy.addView(label(new SimpleDateFormat("MMMM yyyy", new Locale("es", "ES")).format(new Date()), 15, muted, false));
        row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));

        Button settings = new Button(this);
        settings.setText("*");
        settings.setTextSize(24);
        settings.setTextColor(accent);
        settings.setTypeface(Typeface.DEFAULT_BOLD);
        settings.setAllCaps(false);
        settings.setBackground(rounded(surface, 14));
        settings.setOnClickListener(v -> showSettingsDialog());
        row.addView(settings, new LinearLayout.LayoutParams(dp(46), dp(46)));
        return row;
    }

    private View balanceCard() {
        LinearLayout card = card();
        card.addView(label("Saldo disponible", 15, muted, true));
        TextView amount = label(currency(available()), 40, available() >= 0 ? positive : danger, true);
        amount.setPadding(0, dp(8), 0, dp(8));
        card.addView(amount);

        LinearLayout stats = new LinearLayout(this);
        stats.setOrientation(LinearLayout.HORIZONTAL);
        stats.addView(stat("Ingresos", currency(incomeTotal())), new LinearLayout.LayoutParams(0, dp(42), 1));
        stats.addView(stat("Gastos", currency(spent())), new LinearLayout.LayoutParams(0, dp(42), 1));
        card.addView(stats);
        return withMargins(card, 0, 0, 0, 14);
    }

    private View stat(String title, String value) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.addView(label(title, 13, muted, false));
        box.addView(label(value, 13, muted, true));
        return box;
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
        int percent = (int) Math.round(Math.min(spent() / Math.max(monthlyBudget, 1), 1) * 100);
        bar.setProgress(percent);
        card.addView(withMargins(bar, 0, 14, 0, 10), new LinearLayout.LayoutParams(-1, dp(12)));

        LinearLayout bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.HORIZONTAL);
        bottom.addView(label("Presupuesto " + currency(monthlyBudget), 13, muted, false), new LinearLayout.LayoutParams(0, -2, 1));
        bottom.addView(label(percent + "%", 13, muted, true));
        card.addView(bottom);
        return withMargins(card, 0, 0, 0, 14);
    }

    private View actionRow() {
        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        LinearLayout first = actionLine();
        first.addView(actionButton("Gasto", v -> showMovementDialog(null)), new LinearLayout.LayoutParams(0, dp(46), 1));
        addGap(first);
        first.addView(actionButton("Ingreso", v -> showIncomeDialog()), new LinearLayout.LayoutParams(0, dp(46), 1));
        LinearLayout second = actionLine();
        second.addView(actionButton("Calendario", v -> showCalendarDialog()), new LinearLayout.LayoutParams(0, dp(46), 1));
        addGap(second);
        second.addView(actionButton("Categorias", v -> {
            currentTab = 3;
            showDashboard();
        }), new LinearLayout.LayoutParams(0, dp(46), 1));
        grid.addView(first);
        grid.addView(withMargins(second, 0, 10, 0, 0));
        return withMargins(grid, 0, 0, 0, 14);
    }

    private LinearLayout actionLine() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        return row;
    }

    private void addGap(LinearLayout row) {
        row.addView(new View(this), new LinearLayout.LayoutParams(dp(10), 1));
    }

    private Button actionButton(String title, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(title);
        button.setTextColor(accent);
        button.setTypeface(Typeface.DEFAULT_BOLD);
        button.setTextSize(14);
        button.setAllCaps(false);
        button.setBackground(rounded(surface, 8));
        button.setOnClickListener(listener);
        return button;
    }

    private View bottomNav() {
        LinearLayout nav = new LinearLayout(this);
        nav.setOrientation(LinearLayout.HORIZONTAL);
        nav.setGravity(Gravity.CENTER);
        nav.setPadding(dp(6), dp(6), dp(6), dp(6));
        nav.setBackgroundColor(surface);
        String[] labels = {"Inicio", "Analisis", "Movs", "Categorias", "Ajustes"};
        for (int i = 0; i < labels.length; i++) {
            final int index = i;
            TextView item = label(labels[i], 12, currentTab == i ? accent : muted, true);
            item.setGravity(Gravity.CENTER);
            item.setOnClickListener(v -> {
                currentTab = index;
                showDashboard();
            });
            nav.addView(item, new LinearLayout.LayoutParams(0, -1, 1));
        }
        return nav;
    }

    private View insightCard() {
        LinearLayout card = card();
        card.setOnClickListener(v -> showInsightsDialog());
        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.addView(label("Resumen rapido", 16, text, true), new LinearLayout.LayoutParams(0, -2, 1));
        top.addView(label((int) Math.round(savingsRate() * 100) + "% ahorro", 13, positive, true));
        card.addView(top);

        LinearLayout bars = new LinearLayout(this);
        bars.setOrientation(LinearLayout.HORIZONTAL);
        bars.setGravity(Gravity.BOTTOM);
        double max = Math.max(maxCategoryTotal(), 1);
        for (String category : topCategories()) {
            LinearLayout item = new LinearLayout(this);
            item.setOrientation(LinearLayout.VERTICAL);
            item.setGravity(Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
            View bar = new View(this);
            bar.setBackground(rounded(accent, 4));
            item.addView(bar, new LinearLayout.LayoutParams(dp(22), Math.max(dp(14), (int) (dp(74) * totalFor(category) / max))));
            TextView letter = label(category.substring(0, 1), 11, muted, true);
            letter.setGravity(Gravity.CENTER);
            item.addView(letter);
            bars.addView(item, new LinearLayout.LayoutParams(0, dp(96), 1));
        }
        card.addView(withMargins(bars, 0, 12, 0, 6));

        Movement largest = largestExpense();
        if (largest != null) {
            card.addView(label("Mayor gasto: " + largest.title + " · " + currency(largest.amount), 13, muted, false));
        }
        return withMargins(card, 0, 0, 0, 14);
    }

    private View categoryScroller() {
        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (String category : categories) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(12), dp(12), dp(12));
            card.setBackground(rounded(surface, 8));
            card.addView(label(iconFor(category), 18, accent, true));
            card.addView(label(category, 13, text, true));
            card.addView(label(currency(totalFor(category)), 12, muted, false));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(126), dp(104));
            lp.setMargins(0, 0, dp(10), 0);
            row.addView(card, lp);
        }
        scroll.addView(row);
        return withMargins(scroll, 0, 0, 0, 14);
    }

    private View frequentScroller() {
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.setOrientation(LinearLayout.VERTICAL);
        LinearLayout title = new LinearLayout(this);
        title.setOrientation(LinearLayout.HORIZONTAL);
        title.addView(label("Frecuentes", 20, text, true), new LinearLayout.LayoutParams(0, -2, 1));
        title.addView(label("tocar y ajustar", 12, muted, true));
        wrapper.addView(title);

        HorizontalScrollView scroll = new HorizontalScrollView(this);
        scroll.setHorizontalScrollBarEnabled(false);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        for (FrequentExpense item : frequentExpenses) {
            LinearLayout card = new LinearLayout(this);
            card.setOrientation(LinearLayout.VERTICAL);
            card.setPadding(dp(12), dp(12), dp(12), dp(12));
            card.setBackground(rounded(surface, 8));
            card.addView(label("▣", 18, accent, true));
            card.addView(label(item.name, 14, text, true));
            card.addView(label(item.amount > 0 ? currency(item.amount) : "sin importe", 12, muted, false));
            card.setOnClickListener(v -> showMovementDialog(movementFrom(item)));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(134), dp(96));
            lp.setMargins(0, dp(10), dp(10), 0);
            row.addView(card, lp);
        }
        scroll.addView(row);
        wrapper.addView(scroll);
        return withMargins(wrapper, 0, 0, 0, 14);
    }

    private void addFrequentPanel(LinearLayout root) {
        LinearLayout panel = card();
        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.addView(label("Gastos frecuentes", 18, text, true), new LinearLayout.LayoutParams(0, -2, 1));
        header.addView(actionButton("Nuevo", v -> showFrequentDialog(null)), new LinearLayout.LayoutParams(dp(86), dp(42)));
        panel.addView(header);
        panel.addView(label("Conceptos guardados. Pueden llevar importe o quedarse sin dinero.", 13, muted, false));
        for (FrequentExpense item : frequentExpenses) {
            LinearLayout row = new LinearLayout(this);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(0, dp(8), 0, dp(8));
            row.setOnClickListener(v -> showMovementDialog(movementFrom(item)));
            LinearLayout copy = new LinearLayout(this);
            copy.setOrientation(LinearLayout.VERTICAL);
            copy.addView(label(item.name, 15, text, true));
            copy.addView(label(item.category + " · " + (item.amount > 0 ? currency(item.amount) : "sin importe"), 12, muted, false));
            row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));
            row.addView(actionButton("Editar", v -> showFrequentDialog(item)), new LinearLayout.LayoutParams(dp(82), dp(42)));
            row.addView(actionButton("Borrar", v -> {
                frequentExpenses.remove(item);
                saveFrequentExpenses();
                showDashboard();
            }), new LinearLayout.LayoutParams(dp(82), dp(42)));
            panel.addView(row);
        }
        root.addView(withMargins(panel, 0, 0, 0, 14));
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
        row.setOnClickListener(v -> showMovementDialog(item));
        row.setOnLongClickListener(v -> {
            confirmDelete(item);
            return true;
        });

        int kindColor = item.kind.equals("Ingreso") ? positive : accent;
        TextView icon = label(item.category.substring(0, 1), 16, kindColor, true);
        icon.setGravity(Gravity.CENTER);
        icon.setBackground(rounded(withAlpha(kindColor, 28), 8));
        row.addView(icon, new LinearLayout.LayoutParams(dp(42), dp(42)));

        LinearLayout copy = new LinearLayout(this);
        copy.setOrientation(LinearLayout.VERTICAL);
        copy.setPadding(dp(12), 0, 0, 0);
        copy.addView(label(item.title, 16, text, true));
        copy.addView(label(item.category + " · " + item.kind, 13, muted, false));
        row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));

        row.addView(label(currency(item.signedAmount()), 15, item.kind.equals("Ingreso") ? positive : text, true));

        Button more = new Button(this);
        more.setText("...");
        more.setTextColor(muted);
        more.setAllCaps(false);
        more.setBackgroundColor(Color.TRANSPARENT);
        more.setOnClickListener(v -> showMovementOptions(item));
        row.addView(more, new LinearLayout.LayoutParams(dp(48), dp(42)));
        return withMargins(row, 0, 0, 0, 10);
    }

    private LinearLayout card() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(18), dp(18), dp(18), dp(18));
        card.setBackground(rounded(surface, 8));
        return card;
    }

    private void showMovementOptions(Movement movement) {
        new AlertDialog.Builder(this)
            .setItems(new String[]{"Editar", "Borrar"}, (dialog, which) -> {
                if (which == 0) showMovementDialog(movement);
                else confirmDelete(movement);
            })
            .show();
    }

    private void confirmDelete(Movement movement) {
        new AlertDialog.Builder(this)
            .setTitle("Borrar movimiento")
            .setMessage(movement.title)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Borrar", (dialog, which) -> {
                movements.remove(movement);
                saveMovements();
                showDashboard();
            })
            .show();
    }

    private void showIncomeDialog() {
        Movement movement = new Movement(UUID.randomUUID().toString(), "", categories.isEmpty() ? "General" : categories.get(0), 0, "Ingreso");
        showMovementDialog(movement);
    }

    private void showMovementDialog(Movement existing) {
        Movement draft = existing == null
            ? new Movement(UUID.randomUUID().toString(), "", categories.isEmpty() ? "General" : categories.get(0), 0, "Gasto")
            : new Movement(existing.id, existing.title, existing.category, existing.amount, existing.kind);

        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(10), dp(20), 0);

        Spinner kindInput = new Spinner(this);
        kindInput.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, KINDS));
        kindInput.setSelection(draft.kind.equals("Ingreso") ? 1 : 0);
        kindInput.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                draft.kind = KINDS[position];
            }
            @Override public void onNothingSelected(AdapterView<?> parent) { }
        });
        form.addView(kindInput);

        EditText titleInput = new EditText(this);
        titleInput.setHint("Nombre");
        titleInput.setText(draft.title);
        form.addView(titleInput);

        EditText amountInput = new EditText(this);
        amountInput.setHint("Importe");
        amountInput.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        if (draft.amount > 0) amountInput.setText(String.format(Locale.US, "%.2f", draft.amount));
        form.addView(amountInput);

        Spinner categoryInput = new Spinner(this);
        categoryInput.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, categories));
        int categoryIndex = Math.max(0, categories.indexOf(draft.category));
        categoryInput.setSelection(categoryIndex);
        categoryInput.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                draft.category = categories.get(position);
            }
            @Override public void onNothingSelected(AdapterView<?> parent) { }
        });
        form.addView(categoryInput);

        new AlertDialog.Builder(this)
            .setTitle(existing == null ? "Anadir movimiento" : "Editar movimiento")
            .setView(form)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Guardar", (dialog, which) -> {
                draft.title = titleInput.getText().toString().trim();
                draft.amount = parseAmount(amountInput.getText().toString());
                if (!draft.title.isEmpty() && draft.amount > 0) {
                    int index = indexOfMovement(draft.id);
                    if (index >= 0) movements.set(index, draft);
                    else movements.add(0, draft);
                    saveMovements();
                    showDashboard();
                }
            })
            .show();
    }

    private void showFrequentDialog(FrequentExpense existing) {
        FrequentExpense draft = existing == null
            ? new FrequentExpense(UUID.randomUUID().toString(), "", categories.isEmpty() ? "Comida" : categories.get(0), 0)
            : new FrequentExpense(existing.id, existing.name, existing.category, existing.amount);

        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(10), dp(20), 0);

        EditText nameInput = new EditText(this);
        nameInput.setHint("Nombre");
        nameInput.setText(draft.name);
        form.addView(nameInput);

        EditText amountInput = new EditText(this);
        amountInput.setHint("Importe opcional");
        amountInput.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        if (draft.amount > 0) amountInput.setText(String.format(Locale.US, "%.2f", draft.amount));
        form.addView(amountInput);

        Spinner categoryInput = new Spinner(this);
        categoryInput.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, categories));
        categoryInput.setSelection(Math.max(0, categories.indexOf(draft.category)));
        categoryInput.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                draft.category = categories.get(position);
            }
            @Override public void onNothingSelected(AdapterView<?> parent) { }
        });
        form.addView(categoryInput);

        new AlertDialog.Builder(this)
            .setTitle(existing == null ? "Nuevo frecuente" : "Editar frecuente")
            .setView(form)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Guardar", (dialog, which) -> {
                draft.name = nameInput.getText().toString().trim();
                draft.amount = parseAmount(amountInput.getText().toString());
                if (!draft.name.isEmpty()) {
                    int index = indexOfFrequent(draft.id);
                    if (index >= 0) frequentExpenses.set(index, draft);
                    else frequentExpenses.add(0, draft);
                    addCategory(draft.category);
                    saveFrequentExpenses();
                    showDashboard();
                }
            })
            .show();
    }

    private Movement movementFrom(FrequentExpense item) {
        addCategory(item.category);
        return new Movement(UUID.randomUUID().toString(), item.name, item.category, Math.max(0, item.amount), "Gasto");
    }

    private void addInsights(LinearLayout root) {
        LinearLayout metrics = new LinearLayout(this);
        metrics.setOrientation(LinearLayout.VERTICAL);
        metrics.setBackground(rounded(surface, 8));
        metrics.setPadding(dp(14), dp(14), dp(14), dp(14));
        LinearLayout lineOne = actionLine();
        lineOne.addView(metricTile("Ingresos", currency(incomeTotal()), positive), new LinearLayout.LayoutParams(0, dp(72), 1));
        addGap(lineOne);
        lineOne.addView(metricTile("Gastos", currency(spent()), danger), new LinearLayout.LayoutParams(0, dp(72), 1));
        LinearLayout lineTwo = actionLine();
        lineTwo.addView(metricTile("Disponible", currency(available()), available() >= 0 ? positive : danger), new LinearLayout.LayoutParams(0, dp(72), 1));
        addGap(lineTwo);
        lineTwo.addView(metricTile("Ahorro", (int) Math.round(savingsRate() * 100) + "%", accent), new LinearLayout.LayoutParams(0, dp(72), 1));
        metrics.addView(lineOne);
        metrics.addView(withMargins(lineTwo, 0, 10, 0, 0));
        root.addView(withMargins(metrics, 0, 0, 0, 14));

        LinearLayout chart = new LinearLayout(this);
        chart.setOrientation(LinearLayout.VERTICAL);
        chart.setBackground(rounded(surface, 8));
        chart.setPadding(dp(14), dp(14), dp(14), dp(14));
        chart.addView(label("Gastos por categoria", 17, text, true));
        double max = Math.max(maxCategoryTotal(), 1);
        ArrayList<String> ordered = topCategories();
        if (ordered.isEmpty()) {
            TextView empty = label("Todavia no hay gastos para graficar.", 14, muted, false);
            empty.setGravity(Gravity.CENTER);
            chart.addView(empty, new LinearLayout.LayoutParams(-1, dp(90)));
        } else {
            for (String category : ordered) {
                chart.addView(categoryBar(category, totalFor(category), max));
            }
        }
        root.addView(withMargins(chart, 0, 0, 0, 14));

        LinearLayout budget = new LinearLayout(this);
        budget.setOrientation(LinearLayout.VERTICAL);
        budget.setBackground(rounded(surface, 8));
        budget.setPadding(dp(14), dp(14), dp(14), dp(14));
        budget.addView(label("Presupuesto", 17, text, true));
        ProgressBar bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        int percent = (int) Math.round(Math.min(spent() / Math.max(monthlyBudget, 1), 1) * 100);
        bar.setMax(100);
        bar.setProgress(percent);
        budget.addView(withMargins(bar, 0, 14, 0, 10), new LinearLayout.LayoutParams(-1, dp(12)));
        budget.addView(label("Has usado " + percent + "% de " + currency(monthlyBudget), 14, muted, false));
        root.addView(budget);
    }

    private void addCategoriesPage(LinearLayout root) {
        Button add = actionButton("Anadir categoria", v -> showAddCategoryDialog());
        root.addView(withMargins(add, 0, 0, 0, 14), new LinearLayout.LayoutParams(-1, dp(48)));
        for (String category : new ArrayList<>(categories)) {
            LinearLayout card = card();
            LinearLayout row = new LinearLayout(this);
            row.setGravity(Gravity.CENTER_VERTICAL);
            LinearLayout copy = new LinearLayout(this);
            copy.setOrientation(LinearLayout.VERTICAL);
            copy.addView(label(category, 17, text, true));
            copy.addView(label(currency(totalFor(category)), 13, muted, false));
            row.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));
            row.addView(actionButton("Editar", v -> showRenameCategoryDialog(category)), new LinearLayout.LayoutParams(dp(82), dp(42)));
            row.addView(actionButton("Borrar", v -> confirmDeleteCategory(category)), new LinearLayout.LayoutParams(dp(82), dp(42)));
            card.addView(row);
            root.addView(withMargins(card, 0, 0, 0, 10));
        }
    }

    private void addSettingsPage(LinearLayout root) {
        LinearLayout money = card();
        money.addView(label("Dinero del mes", 17, text, true));
        money.addView(label("Ingresos fijos: " + currency(monthlyIncome), 15, muted, false));
        money.addView(label("Presupuesto: " + currency(monthlyBudget), 15, muted, false));
        money.addView(withMargins(actionButton("Editar dinero y tema", v -> showSettingsDialog()), 0, 12, 0, 0), new LinearLayout.LayoutParams(-1, dp(48)));
        root.addView(withMargins(money, 0, 0, 0, 14));

        LinearLayout theme = card();
        theme.addView(label("Apariencia", 17, text, true));
        theme.addView(label("Modo actual: " + MODES[appearanceMode], 15, muted, false));
        root.addView(theme);
    }

    private void showSettingsDialog() {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(10), dp(20), 0);

        EditText incomeInput = new EditText(this);
        incomeInput.setHint("Ingresos fijos");
        incomeInput.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        incomeInput.setText(String.format(Locale.US, "%.2f", monthlyIncome));
        form.addView(incomeInput);

        EditText budgetInput = new EditText(this);
        budgetInput.setHint("Presupuesto de gastos");
        budgetInput.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        budgetInput.setText(String.format(Locale.US, "%.2f", monthlyBudget));
        form.addView(budgetInput);

        Spinner modeInput = new Spinner(this);
        modeInput.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, MODES));
        modeInput.setSelection(appearanceMode);
        final int[] selectedMode = {appearanceMode};
        modeInput.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                selectedMode[0] = position;
            }
            @Override public void onNothingSelected(AdapterView<?> parent) { }
        });
        form.addView(modeInput);

        new AlertDialog.Builder(this)
            .setTitle("Ajustes")
            .setView(form)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Guardar", (dialog, which) -> {
                monthlyIncome = fallback(parseAmount(incomeInput.getText().toString()), monthlyIncome);
                monthlyBudget = fallback(parseAmount(budgetInput.getText().toString()), monthlyBudget);
                appearanceMode = selectedMode[0];
                saveSettings();
                configureColors();
                showDashboard();
            })
            .show();
    }

    private void showInsightsDialog() {
        ScrollView scroll = new ScrollView(this);
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.setOrientation(LinearLayout.VERTICAL);
        wrapper.setPadding(dp(18), dp(8), dp(18), dp(8));
        scroll.addView(wrapper);

        LinearLayout metrics = new LinearLayout(this);
        metrics.setOrientation(LinearLayout.VERTICAL);
        metrics.setBackground(rounded(surface, 8));
        metrics.setPadding(dp(14), dp(14), dp(14), dp(14));
        LinearLayout lineOne = actionLine();
        lineOne.addView(metricTile("Ingresos", currency(incomeTotal()), positive), new LinearLayout.LayoutParams(0, dp(72), 1));
        addGap(lineOne);
        lineOne.addView(metricTile("Gastos", currency(spent()), danger), new LinearLayout.LayoutParams(0, dp(72), 1));
        LinearLayout lineTwo = actionLine();
        lineTwo.addView(metricTile("Disponible", currency(available()), available() >= 0 ? positive : danger), new LinearLayout.LayoutParams(0, dp(72), 1));
        addGap(lineTwo);
        lineTwo.addView(metricTile("Ahorro", (int) Math.round(savingsRate() * 100) + "%", accent), new LinearLayout.LayoutParams(0, dp(72), 1));
        metrics.addView(lineOne);
        metrics.addView(withMargins(lineTwo, 0, 10, 0, 0));
        wrapper.addView(withMargins(metrics, 0, 0, 0, 14));

        LinearLayout chart = new LinearLayout(this);
        chart.setOrientation(LinearLayout.VERTICAL);
        chart.setBackground(rounded(surface, 8));
        chart.setPadding(dp(14), dp(14), dp(14), dp(14));
        chart.addView(label("Gastos por categoria", 17, text, true));
        double max = Math.max(maxCategoryTotal(), 1);
        ArrayList<String> ordered = topCategories();
        if (ordered.isEmpty()) {
            TextView empty = label("Todavia no hay gastos para graficar.", 14, muted, false);
            empty.setGravity(Gravity.CENTER);
            chart.addView(empty, new LinearLayout.LayoutParams(-1, dp(90)));
        } else {
            for (String category : ordered) {
                chart.addView(categoryBar(category, totalFor(category), max));
            }
        }
        wrapper.addView(withMargins(chart, 0, 0, 0, 14));

        LinearLayout budget = new LinearLayout(this);
        budget.setOrientation(LinearLayout.VERTICAL);
        budget.setBackground(rounded(surface, 8));
        budget.setPadding(dp(14), dp(14), dp(14), dp(14));
        budget.addView(label("Presupuesto", 17, text, true));
        ProgressBar bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        int percent = (int) Math.round(Math.min(spent() / Math.max(monthlyBudget, 1), 1) * 100);
        bar.setMax(100);
        bar.setProgress(percent);
        budget.addView(withMargins(bar, 0, 14, 0, 10), new LinearLayout.LayoutParams(-1, dp(12)));
        budget.addView(label("Has usado " + percent + "% de " + currency(monthlyBudget), 14, muted, false));
        wrapper.addView(budget);

        new AlertDialog.Builder(this)
            .setTitle("Analisis")
            .setView(scroll)
            .setPositiveButton("Cerrar", null)
            .show();
    }

    private void showCalendarDialog() {
        ScrollView scroll = new ScrollView(this);
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.setOrientation(LinearLayout.VERTICAL);
        wrapper.setPadding(dp(18), dp(8), dp(18), dp(8));
        scroll.addView(wrapper);

        Calendar calendar = Calendar.getInstance();
        int today = calendar.get(Calendar.DAY_OF_MONTH);
        int maxDay = calendar.getActualMaximum(Calendar.DAY_OF_MONTH);
        LinearLayout grid = new LinearLayout(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        grid.setBackground(rounded(surface, 8));
        grid.setPadding(dp(10), dp(10), dp(10), dp(10));

        for (int start = 1; start <= maxDay; start += 7) {
            LinearLayout row = new LinearLayout(this);
            row.setOrientation(LinearLayout.HORIZONTAL);
            for (int day = start; day < start + 7 && day <= maxDay; day++) {
                final int selectedDay = day;
                Calendar date = Calendar.getInstance();
                date.set(Calendar.DAY_OF_MONTH, selectedDay);
                double expense = totalOn(date, "Gasto");
                double income = totalOn(date, "Ingreso");
                TextView cell = label(String.valueOf(day) + "\n" + (expense > 0 ? "•" : " ") + (income > 0 ? "•" : " "), 13, day == today ? Color.WHITE : text, true);
                cell.setGravity(Gravity.CENTER);
                cell.setBackground(rounded(day == today ? accent : background, 8));
                cell.setOnClickListener(v -> showDayDialog(selectedDay));
                LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(54), 1);
                lp.setMargins(dp(3), dp(3), dp(3), dp(3));
                row.addView(cell, lp);
            }
            grid.addView(row);
        }
        wrapper.addView(grid);

        new AlertDialog.Builder(this)
            .setTitle("Calendario")
            .setView(scroll)
            .setPositiveButton("Cerrar", null)
            .show();
    }

    private void showDayDialog(int day) {
        Calendar date = Calendar.getInstance();
        date.set(Calendar.DAY_OF_MONTH, day);
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.setOrientation(LinearLayout.VERTICAL);
        wrapper.setPadding(dp(18), dp(8), dp(18), dp(8));
        wrapper.addView(label("Gastos: " + currency(totalOn(date, "Gasto")), 15, muted, false));
        wrapper.addView(label("Ingresos: " + currency(totalOn(date, "Ingreso")), 15, muted, false));
        for (Movement movement : movementsOn(date)) {
            wrapper.addView(movementRow(movement));
        }
        new AlertDialog.Builder(this)
            .setTitle("Dia " + day)
            .setView(wrapper)
            .setNegativeButton("Cerrar", null)
            .setPositiveButton("Anadir", (dialog, which) -> showMovementDialog(new Movement(UUID.randomUUID().toString(), "", categories.isEmpty() ? "General" : categories.get(0), 0, "Gasto")))
            .show();
    }

    private View metricTile(String title, String value, int color) {
        LinearLayout tile = new LinearLayout(this);
        tile.setOrientation(LinearLayout.VERTICAL);
        tile.setPadding(dp(12), dp(10), dp(12), dp(10));
        tile.setBackground(rounded(background, 8));
        tile.addView(label(title, 13, muted, true));
        TextView val = label(value, 18, color, true);
        val.setSingleLine(true);
        tile.addView(val);
        return tile;
    }

    private View categoryBar(String category, double amount, double max) {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(0, dp(12), 0, 0);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.addView(label(category, 14, text, true), new LinearLayout.LayoutParams(0, -2, 1));
        row.addView(label(currency(amount), 13, muted, true));
        box.addView(row);

        FrameLayout track = new FrameLayout(this);
        track.setBackground(rounded(background, 5));
        View fill = new View(this);
        fill.setBackground(rounded(accent, 5));
        int fillWidth = Math.max(dp(8), (int) (getResources().getDisplayMetrics().widthPixels * 0.72 * amount / max));
        track.addView(fill, new FrameLayout.LayoutParams(fillWidth, dp(10), Gravity.LEFT));
        box.addView(withMargins(track, 0, 7, 0, 0), new LinearLayout.LayoutParams(-1, dp(10)));
        return box;
    }

    private void showCategoriesDialog() {
        LinearLayout wrapper = new LinearLayout(this);
        wrapper.setOrientation(LinearLayout.VERTICAL);
        wrapper.setPadding(dp(18), dp(8), dp(18), 0);

        for (String category : new ArrayList<>(categories)) {
            LinearLayout row = new LinearLayout(this);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.addView(label(category, 16, text, true), new LinearLayout.LayoutParams(0, dp(46), 1));

            Button edit = actionButton("Editar", v -> showRenameCategoryDialog(category));
            row.addView(edit, new LinearLayout.LayoutParams(dp(86), dp(42)));

            Button delete = actionButton("Borrar", v -> confirmDeleteCategory(category));
            delete.setEnabled(categories.size() > 1);
            row.addView(delete, new LinearLayout.LayoutParams(dp(86), dp(42)));
            wrapper.addView(row);
        }

        new AlertDialog.Builder(this)
            .setTitle("Categorias")
            .setView(wrapper)
            .setNegativeButton("Cerrar", null)
            .setPositiveButton("Anadir", (dialog, which) -> showAddCategoryDialog())
            .show();
    }

    private void showAddCategoryDialog() {
        EditText input = new EditText(this);
        input.setHint("Nombre");
        new AlertDialog.Builder(this)
            .setTitle("Nueva categoria")
            .setView(input)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Guardar", (dialog, which) -> {
                addCategory(input.getText().toString());
                showDashboard();
            })
            .show();
    }

    private void showRenameCategoryDialog(String oldName) {
        EditText input = new EditText(this);
        input.setText(oldName);
        new AlertDialog.Builder(this)
            .setTitle("Editar categoria")
            .setView(input)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Guardar", (dialog, which) -> {
                renameCategory(oldName, input.getText().toString());
                showDashboard();
            })
            .show();
    }

    private void confirmDeleteCategory(String category) {
        new AlertDialog.Builder(this)
            .setTitle("Borrar categoria")
            .setMessage(category)
            .setNegativeButton("Cancelar", null)
            .setPositiveButton("Borrar", (dialog, which) -> {
                deleteCategory(category);
                showDashboard();
            })
            .show();
    }

    private void loadSettings() {
        monthlyIncome = Double.longBitsToDouble(prefs.getLong("monthlyIncome", Double.doubleToLongBits(1850)));
        monthlyBudget = Double.longBitsToDouble(prefs.getLong("monthlyBudget", Double.doubleToLongBits(1200)));
        appearanceMode = prefs.getInt("appearanceMode", 0);
    }

    private void saveSettings() {
        prefs.edit()
            .putLong("monthlyIncome", Double.doubleToLongBits(monthlyIncome))
            .putLong("monthlyBudget", Double.doubleToLongBits(monthlyBudget))
            .putInt("appearanceMode", appearanceMode)
            .apply();
    }

    private void loadCategories() {
        categories.clear();
        String raw = prefs.getString("categories", "");
        if (!raw.isEmpty()) {
            try {
                JSONArray array = new JSONArray(raw);
                for (int i = 0; i < array.length(); i++) categories.add(array.getString(i));
            } catch (Exception ignored) {
                categories.clear();
            }
        }
        if (categories.isEmpty()) {
            for (String category : DEFAULT_CATEGORIES) categories.add(category);
        }
    }

    private void saveCategories() {
        JSONArray array = new JSONArray();
        for (String category : categories) array.put(category);
        prefs.edit().putString("categories", array.toString()).apply();
    }

    private void loadFrequentExpenses() {
        frequentExpenses.clear();
        String raw = prefs.getString("frequent.expenses.v1", "");
        if (!raw.isEmpty()) {
            try {
                JSONArray array = new JSONArray(raw);
                for (int i = 0; i < array.length(); i++) frequentExpenses.add(FrequentExpense.from(array.getJSONObject(i)));
            } catch (Exception ignored) {
                frequentExpenses.clear();
            }
        }
        if (frequentExpenses.isEmpty()) {
            frequentExpenses.add(new FrequentExpense(UUID.randomUUID().toString(), "Supermercado", "Comida", 0));
            frequentExpenses.add(new FrequentExpense(UUID.randomUUID().toString(), "Gasolina", "Transporte", 0));
            frequentExpenses.add(new FrequentExpense(UUID.randomUUID().toString(), "Alquiler", "Casa", 0));
            frequentExpenses.add(new FrequentExpense(UUID.randomUUID().toString(), "Luz", "Casa", 0));
            frequentExpenses.add(new FrequentExpense(UUID.randomUUID().toString(), "Farmacia", "Salud", 0));
            frequentExpenses.add(new FrequentExpense(UUID.randomUUID().toString(), "Restaurante", "Ocio", 0));
            frequentExpenses.add(new FrequentExpense(UUID.randomUUID().toString(), "Gimnasio", "Salud", 0));
            frequentExpenses.add(new FrequentExpense(UUID.randomUUID().toString(), "Suscripciones", "Ocio", 0));
        }
    }

    private void saveFrequentExpenses() {
        JSONArray array = new JSONArray();
        try {
            for (FrequentExpense item : frequentExpenses) array.put(item.toJson());
        } catch (Exception ignored) { }
        prefs.edit().putString("frequent.expenses.v1", array.toString()).apply();
    }

    private void addCategory(String value) {
        String cleaned = value.trim();
        if (cleaned.isEmpty() || categories.contains(cleaned)) return;
        categories.add(cleaned);
        saveCategories();
    }

    private void renameCategory(String oldName, String newName) {
        String cleaned = newName.trim();
        if (cleaned.isEmpty()) return;
        int index = categories.indexOf(oldName);
        if (index >= 0) categories.set(index, cleaned);
        for (Movement movement : movements) {
            if (movement.category.equals(oldName)) movement.category = cleaned;
        }
        saveCategories();
        saveMovements();
    }

    private void deleteCategory(String category) {
        if (categories.size() <= 1) return;
        categories.remove(category);
        String fallback = categories.isEmpty() ? "General" : categories.get(0);
        for (Movement movement : movements) {
            if (movement.category.equals(category)) movement.category = fallback;
        }
        saveCategories();
        saveMovements();
    }

    private void loadMovements() {
        movements.clear();
        String raw = prefs.getString("movements.v2", "");
        if (raw.isEmpty()) raw = prefs.getString("movements", "");
        if (!raw.isEmpty()) {
            try {
                JSONArray array = new JSONArray(raw);
                for (int i = 0; i < array.length(); i++) {
                    JSONObject item = array.getJSONObject(i);
                    String kind = item.optString("kind", item.optDouble("amount") >= 0 ? "Ingreso" : "Gasto");
                    double amount = Math.abs(item.getDouble("amount"));
                    movements.add(new Movement(
                        item.optString("id", UUID.randomUUID().toString()),
                        item.getString("title"),
                        item.getString("category"),
                        amount,
                        kind
                    ));
                }
                return;
            } catch (Exception ignored) {
                movements.clear();
            }
        }
        movements.add(new Movement(UUID.randomUUID().toString(), "Supermercado", "Comida", 46.20, "Gasto"));
        movements.add(new Movement(UUID.randomUUID().toString(), "Metro", "Transporte", 12.80, "Gasto"));
        movements.add(new Movement(UUID.randomUUID().toString(), "Alquiler", "Casa", 620, "Gasto"));
    }

    private void saveMovements() {
        JSONArray array = new JSONArray();
        try {
            for (Movement movement : movements) {
                JSONObject item = new JSONObject();
                item.put("id", movement.id);
                item.put("title", movement.title);
                item.put("category", movement.category);
                item.put("amount", movement.amount);
                item.put("kind", movement.kind);
                array.put(item);
            }
        } catch (Exception ignored) { }
        prefs.edit().putString("movements.v2", array.toString()).apply();
    }

    private int indexOfMovement(String id) {
        for (int i = 0; i < movements.size(); i++) {
            if (movements.get(i).id.equals(id)) return i;
        }
        return -1;
    }

    private int indexOfFrequent(String id) {
        for (int i = 0; i < frequentExpenses.size(); i++) {
            if (frequentExpenses.get(i).id.equals(id)) return i;
        }
        return -1;
    }

    private double incomeTotal() {
        double total = monthlyIncome;
        for (Movement movement : movements) {
            if (movement.kind.equals("Ingreso")) total += movement.amount;
        }
        return total;
    }

    private double spent() {
        double total = 0;
        for (Movement movement : movements) {
            if (movement.kind.equals("Gasto")) total += movement.amount;
        }
        return total;
    }

    private double available() {
        return incomeTotal() - spent();
    }

    private double savingsRate() {
        if (incomeTotal() <= 0) return 0;
        return Math.max(0, Math.min(available() / incomeTotal(), 1));
    }

    private double totalFor(String category) {
        double total = 0;
        for (Movement movement : movements) {
            if (movement.category.equals(category) && movement.kind.equals("Gasto")) total += movement.amount;
        }
        return total;
    }

    private double totalOn(Calendar date, String kind) {
        if (date.get(Calendar.DAY_OF_MONTH) != Calendar.getInstance().get(Calendar.DAY_OF_MONTH)) return 0;
        double total = 0;
        for (Movement movement : movements) {
            if (movement.kind.equals(kind)) total += movement.amount;
        }
        return total;
    }

    private ArrayList<Movement> movementsOn(Calendar date) {
        ArrayList<Movement> result = new ArrayList<>();
        if (date.get(Calendar.DAY_OF_MONTH) != Calendar.getInstance().get(Calendar.DAY_OF_MONTH)) return result;
        result.addAll(movements);
        return result;
    }

    private double maxCategoryTotal() {
        double max = 0;
        for (String category : categories) max = Math.max(max, totalFor(category));
        return max;
    }

    private ArrayList<String> topCategories() {
        ArrayList<String> ordered = new ArrayList<>(categories);
        ordered.removeIf(category -> totalFor(category) <= 0);
        ordered.sort((a, b) -> Double.compare(totalFor(b), totalFor(a)));
        return ordered;
    }

    private Movement largestExpense() {
        Movement largest = null;
        for (Movement movement : movements) {
            if (!movement.kind.equals("Gasto")) continue;
            if (largest == null || movement.amount > largest.amount) largest = movement;
        }
        return largest;
    }

    private double parseAmount(String value) {
        try {
            return Double.parseDouble(value.replace(",", "."));
        } catch (Exception e) {
            return 0;
        }
    }

    private double fallback(double value, double fallback) {
        return value > 0 ? value : fallback;
    }

    private String currency(double value) {
        NumberFormat format = NumberFormat.getCurrencyInstance(new Locale("es", "ES"));
        return format.format(value);
    }

    private String iconFor(String category) {
        if ("Casa".equals(category)) return "H";
        if ("Comida".equals(category)) return "C";
        if ("Transporte".equals(category)) return "T";
        return "#";
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
        final String id;
        String title;
        String category;
        double amount;
        String kind;

        Movement(String id, String title, String category, double amount, String kind) {
            this.id = id;
            this.title = title;
            this.category = category;
            this.amount = amount;
            this.kind = kind;
        }

        double signedAmount() {
            return kind.equals("Ingreso") ? amount : -amount;
        }
    }

    private static final class FrequentExpense {
        final String id;
        String name;
        String category;
        double amount;

        FrequentExpense(String id, String name, String category, double amount) {
            this.id = id;
            this.name = name;
            this.category = category;
            this.amount = amount;
        }

        JSONObject toJson() throws Exception {
            JSONObject json = new JSONObject();
            json.put("id", id);
            json.put("name", name);
            json.put("category", category);
            json.put("amount", amount);
            return json;
        }

        static FrequentExpense from(JSONObject json) {
            return new FrequentExpense(
                json.optString("id", UUID.randomUUID().toString()),
                json.optString("name", ""),
                json.optString("category", "Comida"),
                json.optDouble("amount", 0)
            );
        }
    }
}
