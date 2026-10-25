/*
 * This is the source code of AyuGram for Android.
 *
 * We do not and cannot prevent the use of our code,
 * but be respectful and credit the original author.
 *
 * Copyright @Radolyn, 2023
 */

package tw.nekomimi.nekogram.settings;

import android.content.Context;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import org.telegram.messenger.*;
import org.telegram.ui.ActionBar.Theme;
import org.telegram.ui.Cells.*;

import java.util.Locale;

import tw.nekomimi.nekogram.NekoConfig;
import tw.nekomimi.nekogram.utils.AyuGhostUtils;

public class NekoGhostModeActivity extends BaseNekoSettingsActivity {
    // title
    private int GhostHeaderRow;
    private int GhostModeTitleRow;

    private int sendReadMessagePacketsRow;
    private int sendOnlinePacketsRow;
    private int sendUploadProgressRow;
    private int sendReadStoryPacketsRow;
    private int sendOfflineAfterOnlineRow;
    private int markReadAfterSendRow;
    private int lockHeaderRow;
    private int lockReadRow;
    private int lockOnlineRow;
    private int lockUploadRow;
    private int lockStoryRow;
    private int lockOfflineRow;
    private int showGhostModeStatusRow;

    private int ghostDividerRow;
    private int DrawerHeaderRow;
    private int showGhostToggleInDrawerRow;
    private boolean ghostModeMenuExpanded;

    @Override
    protected void updateRows() {
        super.updateRows();

        GhostHeaderRow = addRow();
        GhostModeTitleRow = addRow();
        if (ghostModeMenuExpanded) {
            sendReadMessagePacketsRow = addRow();
            sendOnlinePacketsRow = addRow();
            sendUploadProgressRow = addRow();
            sendReadStoryPacketsRow = addRow();
            sendOfflineAfterOnlineRow = addRow();
        } else {
            sendReadMessagePacketsRow = -1;
            sendOnlinePacketsRow = -1;
            sendUploadProgressRow = -1;
            sendReadStoryPacketsRow = -1;
            sendOfflineAfterOnlineRow = -1;
        }
        markReadAfterSendRow = addRow();
        lockHeaderRow = addRow();
        lockReadRow = addRow();
        lockOnlineRow = addRow();
        lockUploadRow = addRow();
        lockStoryRow = addRow();
        lockOfflineRow = addRow();
        showGhostModeStatusRow = addRow();
        ghostDividerRow = addRow();
        DrawerHeaderRow = addRow();
        showGhostToggleInDrawerRow = addRow();
    }

    @Override
    public boolean onFragmentCreate() {
        // todo: register `MESSAGES_DELETED_NOTIFICATION` on all notification centers, not only on the current account
        super.onFragmentCreate();
        return true;
    }

    @Override
    public void onFragmentDestroy() {
        super.onFragmentDestroy();
    }

    private void updateGhostViews() {
        var isActive = NekoConfig.isGhostModeActive();

        listAdapter.notifyItemChanged(GhostModeTitleRow, PARTIAL);
        listAdapter.notifyItemChanged(sendReadMessagePacketsRow, !isActive);
        listAdapter.notifyItemChanged(sendOnlinePacketsRow, !isActive);
        listAdapter.notifyItemChanged(sendUploadProgressRow, !isActive);
        listAdapter.notifyItemChanged(sendReadStoryPacketsRow,!isActive);
        listAdapter.notifyItemChanged(sendOfflineAfterOnlineRow, isActive);

        NotificationCenter.getInstance(UserConfig.selectedAccount).postNotificationName(NotificationCenter.mainUserInfoChanged);
    }


    @Override
    protected void onItemClick(View view, int position, float x, float y) {
        if (position == GhostModeTitleRow) {
            ghostModeMenuExpanded ^= true;
            updateRows();
            listAdapter.notifyItemChanged(GhostModeTitleRow, PARTIAL);
            if (ghostModeMenuExpanded) {
                listAdapter.notifyItemRangeInserted(GhostModeTitleRow + 1, 5);
            } else {
                listAdapter.notifyItemRangeRemoved(GhostModeTitleRow + 1, 5);
            }
        } else if (position == sendReadMessagePacketsRow) {
            NekoConfig.putBoolean("sendReadMessagePackets", NekoConfig.sendReadMessagePackets ^= true);
            ((CheckBoxCell) view).setChecked(NekoConfig.sendReadMessagePackets, true);
            AyuGhostUtils.setAllowReadPacket(false, -1);
            updateGhostViews();
        } else if (position == sendOnlinePacketsRow) {
            NekoConfig.putBoolean("sendOnlinePackets", NekoConfig.sendOnlinePackets ^= true);
            ((CheckBoxCell) view).setChecked(NekoConfig.sendOnlinePackets, true);
            updateGhostViews();
        } else if (position == sendUploadProgressRow) {
            NekoConfig.putBoolean("sendUploadProgress", NekoConfig.sendUploadProgress ^= true);
            ((CheckBoxCell) view).setChecked(NekoConfig.sendUploadProgress, true);
            updateGhostViews();
        } else if (position == sendReadStoryPacketsRow) {
            NekoConfig.putBoolean("sendReadStoryPackets", NekoConfig.sendReadStoryPackets ^= true);
            ((CheckBoxCell) view).setChecked(NekoConfig.sendReadStoryPackets, true);
            updateGhostViews();
        } else if (position == sendOfflineAfterOnlineRow) {
            NekoConfig.putBoolean("sendOfflineAfterOnline", NekoConfig.sendOfflineAfterOnline ^= true);
            ((CheckBoxCell) view).setChecked(NekoConfig.sendOfflineAfterOnline, true);
            updateGhostViews();
        } else if (position == markReadAfterSendRow) {
            NekoConfig.putBoolean("markReadAfterSend", NekoConfig.markReadAfterSend ^= true);
            ((TextCheckCell) view).setChecked(NekoConfig.markReadAfterSend);
            AyuGhostUtils.setAllowReadPacket(false, -1);
        } else if (position == lockReadRow) {
            toggleLock("sendReadMessagePacketsLocked", (TextCheckCell) view);
        } else if (position == lockOnlineRow) {
            toggleLock("sendOnlinePacketsLocked", (TextCheckCell) view);
        } else if (position == lockUploadRow) {
            toggleLock("sendUploadProgressLocked", (TextCheckCell) view);
        } else if (position == lockStoryRow) {
            toggleLock("sendReadStoryPacketsLocked", (TextCheckCell) view);
        } else if (position == lockOfflineRow) {
            toggleLock("sendOfflineAfterOnlineLocked", (TextCheckCell) view);
        } else if (position == showGhostModeStatusRow) {
            NekoConfig.showGhostModeStatus ^= true;
            NekoConfig.putBoolean("showGhostModeStatus", NekoConfig.showGhostModeStatus);
            ((TextCheckCell) view).setChecked(NekoConfig.showGhostModeStatus);
            NotificationCenter.getInstance(UserConfig.selectedAccount).postNotificationName(NotificationCenter.mainUserInfoChanged);
        } else if (position == showGhostToggleInDrawerRow) {
            NekoConfig.putBoolean("showGhostToggleInDrawer", NekoConfig.showGhostToggleInDrawer ^= true);
            ((TextCheckCell) view).setChecked(NekoConfig.showGhostToggleInDrawer);

            NotificationCenter.getInstance(UserConfig.selectedAccount).postNotificationName(NotificationCenter.mainUserInfoChanged);
        }
    }

    private void toggleLock(String key, TextCheckCell cell) {
        boolean value = !NekoConfig.isGhostLocked(key);
        NekoConfig.setGhostLocked(key, value);
        cell.setChecked(value);
    }

    @Override
    protected String getActionBarTitle() {
        return LocaleController.getString(R.string.GhostMode);
    }

    @Override
    protected BaseListAdapter createAdapter(Context context) {
        return new ListAdapter(context);
    }

    private int getGhostModeSelectedCount() {
        int count = 0;
        if (!NekoConfig.sendReadMessagePackets) count++;
        if (!NekoConfig.sendOnlinePackets) count++;
        if (!NekoConfig.sendUploadProgress) count++;
        if (!NekoConfig.sendReadStoryPackets) count++;
        if (NekoConfig.sendOfflineAfterOnline) count++;
        return count;
    }

    private class ListAdapter extends BaseListAdapter {

        public ListAdapter(Context context) {
            super(context);
        }

        @Override
        public void onBindViewHolder(@NonNull RecyclerView.ViewHolder holder, int position, boolean payload, boolean divider) {
            switch (holder.getItemViewType()) {
                case TYPE_SHADOW:
                    holder.itemView.setBackground(Theme.getThemedDrawable(mContext, R.drawable.greydivider, Theme.key_windowBackgroundGrayShadow));
                    break;
                case TYPE_HEADER:
                    HeaderCell headerCell = (HeaderCell) holder.itemView;
                    if (position == GhostHeaderRow) {
                        headerCell.setText(LocaleController.getString(R.string.GhostElements));
                    }
                    if (position == DrawerHeaderRow) {
                        headerCell.setText(LocaleController.getString(R.string.DrawerElements));
                    }
                    if (position == lockHeaderRow) {
                        headerCell.setText(LocaleController.getString(R.string.GhostLockedElements));
                    }
                    break;
                case TYPE_CHECK:
                    TextCheckCell textCheckCell = (TextCheckCell) holder.itemView;
                    textCheckCell.setEnabled(true, null);
                    if (position == markReadAfterSendRow) {
                        textCheckCell.setTextAndCheck(LocaleController.getString(R.string.MarkReadAfterAction), NekoConfig.markReadAfterSend, divider);
                    } else if (position == showGhostToggleInDrawerRow) {
                        textCheckCell.setTextAndCheck(LocaleController.getString(R.string.GhostMode), NekoConfig.showGhostToggleInDrawer, divider);
                    } else if (position == lockReadRow) {
                        textCheckCell.setTextAndCheck(LocaleController.getString(R.string.LockDontReadMessages), NekoConfig.isGhostLocked("sendReadMessagePacketsLocked"), divider);
                    } else if (position == lockOnlineRow) {
                        textCheckCell.setTextAndCheck(LocaleController.getString(R.string.LockDontSendOnlinePackets), NekoConfig.isGhostLocked("sendOnlinePacketsLocked"), divider);
                    } else if (position == lockUploadRow) {
                        textCheckCell.setTextAndCheck(LocaleController.getString(R.string.LockDontSendUploadProgress), NekoConfig.isGhostLocked("sendUploadProgressLocked"), divider);
                    } else if (position == lockStoryRow) {
                        textCheckCell.setTextAndCheck(LocaleController.getString(R.string.LockDontReadStories), NekoConfig.isGhostLocked("sendReadStoryPacketsLocked"), divider);
                    } else if (position == lockOfflineRow) {
                        textCheckCell.setTextAndCheck(LocaleController.getString(R.string.LockSendOfflinePacketAfterOnline), NekoConfig.isGhostLocked("sendOfflineAfterOnlineLocked"), divider);
                    } else if (position == showGhostModeStatusRow) {
                        textCheckCell.setTextAndCheck(LocaleController.getString(R.string.ShowGhostModeStatus), NekoConfig.showGhostModeStatus, divider);
                    }
                    break;
                case TYPE_CHECK2:
                    TextCheckCell2 textCheckCell2 = (TextCheckCell2) holder.itemView;
                    if (position == GhostModeTitleRow) {
                        int selectedCount = getGhostModeSelectedCount();
                        textCheckCell2.setTextAndCheck(LocaleController.getString(R.string.GhostMode), NekoConfig.isGhostModeActive(), divider, true);
                        textCheckCell2.setCollapseArrow(String.format(Locale.US, "%d/5", selectedCount), !ghostModeMenuExpanded, () -> {
                            NekoConfig.toggleGhostMode();
                            updateGhostViews();
                        });
                    }
                    textCheckCell2.getCheckBox().setColors(Theme.key_switchTrack, Theme.key_switchTrackChecked, Theme.key_windowBackgroundWhite, Theme.key_windowBackgroundWhite);
                    textCheckCell2.getCheckBox().setDrawIconType(0);
                    break;
                case TYPE_CHECKBOX2:
                    CheckBoxCell checkBoxCell = (CheckBoxCell) holder.itemView;
                    if (position == sendReadMessagePacketsRow) {
                        checkBoxCell.setText(LocaleController.getString(R.string.DontReadMessages), "", !NekoConfig.sendReadMessagePackets, divider, true);
                    } else if (position == sendOnlinePacketsRow) {
                        checkBoxCell.setText(LocaleController.getString(R.string.DontSendOnlinePackets), "", !NekoConfig.sendOnlinePackets, divider, true);
                    } else if (position == sendUploadProgressRow) {
                        checkBoxCell.setText(LocaleController.getString(R.string.DontSendUploadProgress), "", !NekoConfig.sendUploadProgress, divider, true);
                    } else if (position == sendReadStoryPacketsRow) {
                        checkBoxCell.setText(LocaleController.getString(R.string.DontReadStories), "", !NekoConfig.sendReadStoryPackets, divider, true);
                    } else if (position == sendOfflineAfterOnlineRow) {
                        checkBoxCell.setText(LocaleController.getString(R.string.SendOfflinePacketAfterOnline), "", NekoConfig.sendOfflineAfterOnline, divider, true);
                    }
                    checkBoxCell.setPad(1);
                    break;
            }
        }

        @Override
        public int getItemViewType(int position) {
            if (position == ghostDividerRow) {
                return TYPE_SHADOW;
            }
            if (position == GhostHeaderRow || position == DrawerHeaderRow || position == lockHeaderRow) {
                return TYPE_HEADER;
            }
            if (position == GhostModeTitleRow) {
                return TYPE_CHECK2;
            }
            if (position >= sendReadMessagePacketsRow && position <= sendOfflineAfterOnlineRow) {
                return TYPE_CHECKBOX2;
            }
            if (position == markReadAfterSendRow || position == showGhostToggleInDrawerRow
                    || position == lockReadRow || position == lockOnlineRow || position == lockUploadRow
                    || position == lockStoryRow || position == lockOfflineRow
                    || position == showGhostModeStatusRow) {
                return TYPE_CHECK;
            }
            return super.getItemViewType(position);
        }
    }
}
