package tw.nekomimi.nekogram.settings;

import android.content.Context;
import android.text.Editable;
import android.text.TextWatcher;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import org.telegram.messenger.AndroidUtilities;
import org.telegram.messenger.LocaleController;
import org.telegram.messenger.R;
import org.telegram.ui.ActionBar.ActionBar;
import org.telegram.ui.ActionBar.BaseFragment;
import org.telegram.ui.ActionBar.Theme;
import org.telegram.ui.Cells.TextSettingsCell;
import org.telegram.ui.Components.LayoutHelper;
import org.telegram.ui.Components.RecyclerListView;
import org.telegram.ui.Components.SearchField;

import java.util.ArrayList;
import java.util.Locale;

import tw.nekomimi.nekogram.helpers.SettingsHelper;
import tw.nekomimi.nekogram.helpers.SettingsSearchResult;

/**
 * Global search across every DuskGram settings page.
 *
 * The index comes from {@link SettingsHelper#onCreateSearchArray}, so it always
 * matches what the settings pages actually expose.
 */
public class DuskSettingsSearchActivity extends BaseFragment {

    private SearchField searchField;
    private RecyclerListView listView;
    private ListAdapter adapter;
    private TextView emptyView;

    private final ArrayList<SettingsSearchResult> allResults = new ArrayList<>();
    private final ArrayList<SettingsSearchResult> filtered = new ArrayList<>();

    @Override
    public boolean onFragmentCreate() {
        allResults.clear();
        allResults.addAll(SettingsHelper.onCreateSearchArray(
                fragment -> AndroidUtilities.runOnUIThread(() -> presentFragment(fragment))
        ));
        return super.onFragmentCreate();
    }

    @Override
    public View createView(Context context) {
        actionBar.setBackButtonImage(R.drawable.ic_ab_back);
        actionBar.setAllowOverlayTitle(true);
        actionBar.setTitle(LocaleController.getString(R.string.DuskSettingsSearch));
        actionBar.setActionBarMenuOnItemClick(new ActionBar.ActionBarMenuOnItemClick() {
            @Override
            public void onItemClick(int id) {
                if (id == -1) {
                    finishFragment();
                }
            }
        });

        FrameLayout content = new FrameLayout(context);
        content.setBackgroundColor(Theme.getColor(Theme.key_windowBackgroundGray));
        fragmentView = content;

        searchField = new SearchField(context, true, getResourceProvider());
        searchField.setHint(LocaleController.getString(R.string.Search));
        searchField.getSearchEditText().addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
            }

            @Override
            public void afterTextChanged(Editable s) {
                filter(s == null ? "" : s.toString());
            }
        });
        content.addView(searchField, LayoutHelper.createFrame(LayoutHelper.MATCH_PARENT, LayoutHelper.WRAP_CONTENT, Gravity.TOP | Gravity.LEFT));

        listView = new RecyclerListView(context, getResourceProvider());
        listView.setLayoutManager(new LinearLayoutManager(context, LinearLayoutManager.VERTICAL, false));
        listView.setVerticalScrollBarEnabled(false);
        listView.setAdapter(adapter = new ListAdapter(context));
        listView.setOnItemClickListener((view, position) -> {
            if (position < 0 || position >= filtered.size()) return;
            SettingsSearchResult result = filtered.get(position);
            if (result.openRunnable != null) {
                result.openRunnable.run();
            }
        });
        content.addView(listView, LayoutHelper.createFrame(LayoutHelper.MATCH_PARENT, LayoutHelper.MATCH_PARENT, Gravity.TOP | Gravity.LEFT, 0, 60, 0, 0));

        emptyView = new TextView(context);
        emptyView.setTextSize(TypedValue.COMPLEX_UNIT_DIP, 15);
        emptyView.setTextColor(Theme.getColor(Theme.key_windowBackgroundWhiteGrayText));
        emptyView.setGravity(Gravity.CENTER);
        emptyView.setText(LocaleController.getString(R.string.NoResult));
        emptyView.setVisibility(View.GONE);
        content.addView(emptyView, LayoutHelper.createFrame(LayoutHelper.MATCH_PARENT, LayoutHelper.WRAP_CONTENT, Gravity.CENTER));

        filter("");
        return fragmentView;
    }

    private void filter(String query) {
        String needle = query == null ? "" : query.trim().toLowerCase(Locale.getDefault());
        filtered.clear();
        for (SettingsSearchResult result : allResults) {
            if (needle.isEmpty()) {
                filtered.add(result);
                continue;
            }
            String title = result.searchTitle == null ? "" : result.searchTitle.toLowerCase(Locale.getDefault());
            String page = result.path2 == null ? "" : result.path2.toLowerCase(Locale.getDefault());
            if (title.contains(needle) || page.contains(needle)) {
                filtered.add(result);
            }
        }
        if (adapter != null) {
            adapter.notifyDataSetChanged();
        }
        if (emptyView != null) {
            emptyView.setVisibility(filtered.isEmpty() && !needle.isEmpty() ? View.VISIBLE : View.GONE);
        }
    }

    private class ListAdapter extends RecyclerListView.SelectionAdapter {

        private final Context context;

        ListAdapter(Context context) {
            this.context = context;
        }

        @Override
        public boolean isEnabled(RecyclerView.ViewHolder holder) {
            return true;
        }

        @Override
        public int getItemCount() {
            return filtered.size();
        }

        @NonNull
        @Override
        public RecyclerView.ViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
            TextSettingsCell cell = new TextSettingsCell(context, getResourceProvider());
            cell.setBackgroundColor(Theme.getColor(Theme.key_windowBackgroundWhite));
            return new RecyclerListView.Holder(cell);
        }

        @Override
        public void onBindViewHolder(@NonNull RecyclerView.ViewHolder holder, int position) {
            SettingsSearchResult result = filtered.get(position);
            TextSettingsCell cell = (TextSettingsCell) holder.itemView;
            String path = result.path2 == null ? "" : result.path2;
            cell.setTextAndValue(result.searchTitle, path, position != filtered.size() - 1);
        }
    }
}
