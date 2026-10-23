package com.raynebaker.aura_pet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/**
 * Home screen widget for Aura Pet.
 *
 * Renders the pet's name, mood, stat bars and the assistant's latest line
 * from the widget storage that PetWidgetService pushes from Dart.
 *
 * Wall-clock decay is mirrored here in Kotlin so the widget stays truthful
 * on system refreshes (updatePeriodMillis) while the app is closed — same
 * formula as Pet.applyDecay in Dart.
 *
 * Feed / Play / Nap buttons fire HomeWidgetBackgroundIntent: Dart's
 * widgetActionCallback runs in a background isolate (the app UI never opens).
 * The Chat button and a tap on the widget body open the app via
 * HomeWidgetLaunchIntent with an aurapet://open?tab= deep link, routed by
 * MainTabs in main.dart.
 */
class AuraPetWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.aura_pet_widget)
            render(context, views, widgetData)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun render(
        context: Context,
        views: RemoteViews,
        d: SharedPreferences,
    ) {
        // Tapping the widget body opens the app on the Pet tab.
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity<MainActivity>(
                context, MainActivity::class.java, Uri.parse("aurapet://open?tab=pet"))
        )

        if (!d.getBoolean("has_pet", false)) {
            views.setViewVisibility(R.id.widget_content, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            return
        }
        views.setViewVisibility(R.id.widget_content, View.VISIBLE)
        views.setViewVisibility(R.id.widget_empty, View.GONE)

        val name = d.getString("pet_name", "Aura").orEmpty()
        val sleeping = d.getBoolean("sleeping", false)

        // Decay the stored stats to "now" so even a stale push reads true.
        val nowMs = System.currentTimeMillis()
        val lastMs = d.getLong("last_updated_ms", nowMs)
        val (hunger, happiness, energy) = applyDecay(
            d.getInt("hunger", 80).toDouble(),
            d.getInt("happiness", 80).toDouble(),
            d.getInt("energy", 90).toDouble(),
            sleeping, lastMs, nowMs,
        )

        val (moodLabel, moodEmoji) = moodFor(hunger, happiness, energy, sleeping)

        views.setTextViewText(R.id.widget_mood_emoji, moodEmoji)
        views.setTextViewText(R.id.widget_title, name)
        views.setTextViewText(R.id.widget_subtitle, moodLabel)
        views.setProgressBar(R.id.widget_bar_hunger, 100, hunger.roundToInt(), false)
        views.setProgressBar(
            R.id.widget_bar_happiness, 100, happiness.roundToInt(), false)
        views.setProgressBar(R.id.widget_bar_energy, 100, energy.roundToInt(), false)
        views.setTextViewText(
            R.id.widget_assistant_line, d.getString("assistant_line", "").orEmpty())

        // Care buttons: handled in Dart, no app UI opens.
        views.setOnClickPendingIntent(
            R.id.widget_btn_feed,
            HomeWidgetBackgroundIntent.getBroadcast(
                context, Uri.parse("aurapet://feed")))
        views.setOnClickPendingIntent(
            R.id.widget_btn_play,
            HomeWidgetBackgroundIntent.getBroadcast(
                context, Uri.parse("aurapet://play")))
        views.setOnClickPendingIntent(
            R.id.widget_btn_sleep,
            HomeWidgetBackgroundIntent.getBroadcast(
                context, Uri.parse("aurapet://sleep")))
        // Chat button: opens the app straight into the Chat tab.
        views.setOnClickPendingIntent(
            R.id.widget_btn_chat,
            HomeWidgetLaunchIntent.getActivity<MainActivity>(
                context, MainActivity::class.java,
                Uri.parse("aurapet://open?tab=chat")))
    }

    /**
     * Mirror of Pet.applyDecay (Dart): hunger empties in ~8h, happiness in
     * ~6h, energy in ~16h while awake; sleeping slows need-decay to 15% and
     * restores energy over ~8h.
     */
    private fun applyDecay(
        hunger: Double,
        happiness: Double,
        energy: Double,
        sleeping: Boolean,
        lastMs: Long,
        nowMs: Long,
    ): Triple<Double, Double, Double> {
        val minutes = TimeUnit.MILLISECONDS.toMinutes(nowMs - lastMs)
        if (minutes <= 0) return Triple(hunger, happiness, energy)
        val hours = minutes / 60.0
        val awakeHours = if (sleeping) hours * 0.15 else hours
        val h = (hunger - awakeHours * (100.0 / 8.0)).coerceIn(0.0, 100.0)
        val ha = (happiness - awakeHours * (100.0 / 6.0)).coerceIn(0.0, 100.0)
        val e = if (sleeping) {
            (energy + hours * (100.0 / 8.0)).coerceIn(0.0, 100.0)
        } else {
            (energy - awakeHours * (100.0 / 16.0)).coerceIn(0.0, 100.0)
        }
        return Triple(h, ha, e)
    }

    /** Mirror of Pet.mood + PetWidgetService.moodEmoji (Dart). */
    private fun moodFor(
        hunger: Double,
        happiness: Double,
        energy: Double,
        sleeping: Boolean,
    ): Pair<String, String> {
        if (sleeping) return "Napping" to "💤"
        return when {
            hunger < 25 -> "Hungry" to "😿"
            energy < 25 -> "Tired" to "😴"
            happiness < 25 -> "Bored" to "😑"
            hunger < 35 || happiness < 35 || energy < 35 -> "Grumpy" to "😾"
            else -> "Content" to "😻"
        }
    }
}
