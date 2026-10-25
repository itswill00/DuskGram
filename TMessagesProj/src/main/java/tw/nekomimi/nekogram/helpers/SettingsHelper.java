package tw.nekomimi.nekogram.helpers;

import static org.telegram.ui.ProfileActivity.sendLogs;

import android.app.Activity;
import android.net.Uri;
import android.text.TextUtils;

import org.telegram.messenger.AndroidUtilities;
import org.telegram.messenger.LocaleController;
import org.telegram.messenger.R;
import org.telegram.ui.ActionBar.BaseFragment;

import java.util.ArrayList;
import java.util.Map;

import tw.nekomimi.nekogram.ChatHistoryActivity;
import tw.nekomimi.nekogram.settings.BaseNekoSettingsActivity;
import tw.nekomimi.nekogram.settings.BaseNekoXSettingsActivity;
import tw.nekomimi.nekogram.config.cell.AbstractConfigCell;
import tw.nekomimi.nekogram.settings.NekoChatSettingsActivity;
import tw.nekomimi.nekogram.settings.NekoAccountSettingsActivity;
import tw.nekomimi.nekogram.settings.NekoDebugSettingsActivity;
import tw.nekomimi.nekogram.settings.NekoExperimentalSettingsActivity;
import tw.nekomimi.nekogram.settings.NekoGeneralSettingsActivity;
import tw.nekomimi.nekogram.settings.NekoEmojiSettingsActivity;
import tw.nekomimi.nekogram.settings.NekoGhostModeActivity;
import tw.nekomimi.nekogram.settings.NekoPasscodeSettingsActivity;
import tw.nekomimi.nekogram.settings.NekoSettingsActivity;
import xyz.nextalone.nagram.network.NetworkLogActivity;

public class SettingsHelper {

    public static void processDeepLink(Activity activity, Uri uri, Callback callback, Runnable unknown) {
        if (uri == null) {
            unknown.run();
            return;
        }
        var segments = uri.getPathSegments();
        if (segments.isEmpty() || segments.size() > 2 || !"nasettings".equals(segments.get(0))) {
            unknown.run();
            return;
        }
        BaseFragment fragment;
        BaseNekoSettingsActivity neko_fragment = null;
        BaseNekoXSettingsActivity nekox_fragment = null;
        if (segments.size() == 1) {
            fragment = new NekoSettingsActivity();
        } else if (PasscodeHelper.getSettingsKey().equals(segments.get(1))) {
            fragment = neko_fragment = new NekoPasscodeSettingsActivity();
        } else {
            switch (segments.get(1)) {
                case "a":
                case "account":
                    fragment = nekox_fragment = new NekoAccountSettingsActivity();
                    break;
                case "about":
                    fragment = neko_fragment = new NekoSettingsActivity();
                    break;
                case "chat":
                case "chats":
                case "c":
                    fragment = nekox_fragment = new NekoChatSettingsActivity();
                    break;
                case "debug":
                case "d":
                    fragment = nekox_fragment = new NekoDebugSettingsActivity();
                    break;
                case "experimental":
                case "e":
                    fragment = nekox_fragment = new NekoExperimentalSettingsActivity();
                    break;
                case "ghostmode":
                case "ghost":
                    fragment = neko_fragment = new NekoGhostModeActivity();
                    break;
                case "emoji":
                    fragment = neko_fragment = new NekoEmojiSettingsActivity();
                    break;
                case "general":
                case "g":
                    fragment = nekox_fragment = new NekoGeneralSettingsActivity();
                    break;
                case "network_logs":
                case "n":
                    fragment = new NetworkLogActivity();
                    break;
                case "recent_dialogs":
                case "r":
                    fragment = new ChatHistoryActivity();
                    break;
                case "send_logs":
                    sendLogs(activity, false);
                    return;
                default:
                    unknown.run();
                    return;
            }
        }
        callback.presentFragment(fragment);
        var row = uri.getQueryParameter("r");
        if (TextUtils.isEmpty(row)) {
            row = uri.getQueryParameter("row");
        }
        var value = uri.getQueryParameter("v");
        if (TextUtils.isEmpty(value)) {
            value = uri.getQueryParameter("value");
        }
        if (!TextUtils.isEmpty(row)) {
            var rowFinal = row;
            if (neko_fragment != null) {
                BaseNekoSettingsActivity finalNeko_fragment = neko_fragment;
                AndroidUtilities.runOnUIThread(() -> finalNeko_fragment.scrollToRow(rowFinal, unknown));
            } else if (nekox_fragment != null) {
                BaseNekoXSettingsActivity finalNekoX_fragment = nekox_fragment;
                if (!TextUtils.isEmpty(value)) {
                    String finalValue = value;
                    AndroidUtilities.runOnUIThread(() -> finalNekoX_fragment.importToRow(rowFinal, finalValue, unknown));
                } else {
                    AndroidUtilities.runOnUIThread(() -> finalNekoX_fragment.scrollToRow(rowFinal, unknown));
                }
            }
        }
    }

    public interface Callback {
        void presentFragment(BaseFragment fragment);
    }

    public static ArrayList<SettingsSearchResult> onCreateSearchArray(Callback callback) {
        ArrayList<SettingsSearchResult> items = new ArrayList<>();
        String section = LocaleController.getString(R.string.N_Config);

        // Every settings page that exposes rows through the ConfigCell system.
        ArrayList<BaseNekoXSettingsActivity> xFragments = new ArrayList<>();
        xFragments.add(new NekoGeneralSettingsActivity());
        xFragments.add(new NekoChatSettingsActivity());
        xFragments.add(new NekoExperimentalSettingsActivity());
        xFragments.add(new NekoDebugSettingsActivity());
        xFragments.add(new NekoAccountSettingsActivity());

        for (BaseNekoXSettingsActivity fragment : xFragments) {
            int drawable = fragment.getDrawable();
            String page = fragment.getTitle();
            int guid = fragment.getBaseGuid();

            // The page itself is reachable even before searching for a single row.
            if (!TextUtils.isEmpty(page)) {
                BaseFragment pageFragment = fragment;
                items.add(new SettingsSearchResult(guid, page, section, null, drawable,
                        () -> callback.presentFragment(pageFragment)));
            }

            // Each row contributes its own title, so custom-titled rows are found too.
            for (Map.Entry<String, AbstractConfigCell> entry : fragment.getSearchRows().entrySet()) {
                String key = entry.getKey();
                for (CharSequence title : fragment.getSearchTitles(entry.getValue())) {
                    guid++;
                    String openTitle = title.toString();
                    Runnable open = () -> {
                        try {
                            BaseNekoXSettingsActivity f = fragment.getClass().getDeclaredConstructor().newInstance();
                            callback.presentFragment(f);
                            AndroidUtilities.runOnUIThread(() -> f.scrollToRow(key, () -> {}));
                        } catch (Exception ignored) {
                        }
                    };
                    items.add(new SettingsSearchResult(guid, openTitle, section, page, drawable, open));
                }
            }
        }

        // Ghost Mode is a separate page with hand-written rows.
        String ghostPage = LocaleController.getString(R.string.GhostMode);
        int ghostIcon = R.drawable.icon_ghost;
        addLegacyRow(items, callback, new NekoGhostModeActivity(), 20000,
                R.string.GhostMode, section, ghostPage, ghostIcon, "ghost");
        addLegacyRow(items, callback, new NekoGhostModeActivity(), 20001,
                R.string.DontReadMessages, section, ghostPage, ghostIcon, "read");
        addLegacyRow(items, callback, new NekoGhostModeActivity(), 20002,
                R.string.DontSendOnlinePackets, section, ghostPage, ghostIcon, "online");
        addLegacyRow(items, callback, new NekoGhostModeActivity(), 20003,
                R.string.DontSendUploadProgress, section, ghostPage, ghostIcon, "upload");
        addLegacyRow(items, callback, new NekoGhostModeActivity(), 20004,
                R.string.DontReadStories, section, ghostPage, ghostIcon, "stories");
        addLegacyRow(items, callback, new NekoGhostModeActivity(), 20005,
                R.string.SendOfflinePacketAfterOnline, section, ghostPage, ghostIcon, "offline");
        addLegacyRow(items, callback, new NekoGhostModeActivity(), 20006,
                R.string.MarkReadAfterAction, section, ghostPage, ghostIcon, "markread");

        return items;
    }

    /** Adds a result that just opens a page; used for pages outside the CellGroup system. */
    private static void addLegacyRow(ArrayList<SettingsSearchResult> items, Callback callback,
                                     BaseFragment fragment, int guid, int titleRes,
                                     String section, String page, int icon, String key) {
        String title = LocaleController.getString(titleRes);
        if (TextUtils.isEmpty(title)) {
            return;
        }
        Runnable open = () -> callback.presentFragment(fragment);
        items.add(new SettingsSearchResult(guid, title, section, page, icon, open));
    }
}
