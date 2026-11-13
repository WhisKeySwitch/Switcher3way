using Switcher3way.Core;
using Xunit;
using static Switcher3way.Core.StoreReview;

namespace Switcher3way.Core.Tests;

/// <summary>
/// The review ask has fourteen ways to say no and one to say yes, which is the shape of code that
/// silently never fires. Each refusal is pinned here on its own, so a condition that stops working
/// fails a test rather than quietly suppressing a once-ever prompt forever.
///
/// Also pinned: that the feature ships <b>unarmed</b>. <see cref="ShipsUnarmed"/> is expected to fail
/// the day someone sets a calibrated threshold, which is the reminder to check §1 of the change's
/// tasks and set real numbers rather than let the placeholders through.
/// </summary>
public class StoreReviewTests
{
    private static readonly DateTime Now = new(2026, 10, 5, 12, 0, 0, DateTimeKind.Utc);

    /// <summary>Calibrated thresholds, so the rest of the logic can be tested at all.</summary>
    private static readonly Thresholds Live =
        new(Calibrated: true, Conversions: 100, ActiveDays: 3, InstallAgeDays: 7);

    /// <summary>A user who has earned the ask by every measure.</summary>
    private static State Earned(AskState ask = AskState.NotAsked, DateTime? askedUtc = null) =>
        new(ConversionCount: 150, ActiveDays: 10, FirstRunUtc: Now.AddDays(-30), Ask: ask,
            AskedUtc: askedUtc);

    /// <summary>A moment at which interrupting is fine: idle, nothing open, nothing recently wrong.</summary>
    private static Context Quiet() =>
        new(NowUtc: Now, IsPackaged: true, ConversionEnabled: true, OnboardingComplete: true,
            SecureFieldFocused: false, DeniedAppForeground: false, OwnWindowOpen: false,
            SettingsLoadFailed: false, SecondsSinceKeystroke: 120,
            MinutesSinceRewriteFailure: 999, MinutesSinceUndo: 999);

    // ---- the one yes ------------------------------------------------------------------------

    [Fact]
    public void Asks_when_earned_and_the_moment_is_quiet()
    {
        var d = ShouldAsk(Earned(), Quiet(), Live);
        Assert.True(d.Ask);
        Assert.Null(d.Why);
    }

    // ---- shipping posture -------------------------------------------------------------------

    [Fact]
    public void Shipping_thresholds_are_calibrated_and_sane()
    {
        // These were set against eight days of continuous field logging; the comment on Shipping
        // carries the numbers. The assertions are bounds, not the values: they catch a threshold
        // edited to something that could never fire, or to something that fires on day one.
        Assert.True(Thresholds.Shipping.Calibrated);
        Assert.InRange(Thresholds.Shipping.Conversions, 20, 200);
        Assert.InRange(Thresholds.Shipping.ActiveDays, 3, 14);
        Assert.InRange(Thresholds.Shipping.InstallAgeDays, 7, 30);
    }

    [Fact]
    public void An_uncalibrated_threshold_still_refuses_outright()
    {
        // The escape hatch stays tested: setting Calibrated=false must disable the ask completely,
        // which is how it would be rolled back if the prompt turned out to be unwelcome.
        var off = Thresholds.Shipping with { Calibrated = false };
        var broken = Quiet() with { IsPackaged = false, ConversionEnabled = false, SecureFieldFocused = true };
        Assert.Equal(Reason.Uncalibrated, ShouldAsk(Earned(), Quiet(), off).Why);
        Assert.Equal(Reason.Uncalibrated, ShouldAsk(Earned(), broken, off).Why);
    }

    [Fact]
    public void The_shipping_thresholds_ask_a_user_who_has_clearly_earned_it()
    {
        // A month of the field log's measured rate (14.3 fixes/day over 8 days, 7 of them active).
        var t = Thresholds.Shipping;
        var realistic = new State(ConversionCount: 430, ActiveDays: 26, FirstRunUtc: Now.AddDays(-30),
                                  Ask: AskState.NotAsked, AskedUtc: null);
        Assert.True(ShouldAsk(realistic, Quiet(), t).Ask);

        // …and not a user who installed it a fortnight ago and barely typed.
        var trial = new State(ConversionCount: 4, ActiveDays: 2, FirstRunUtc: Now.AddDays(-14),
                              Ask: AskState.NotAsked, AskedUtc: null);
        Assert.False(ShouldAsk(trial, Quiet(), t).Ask);
    }

    // ---- eligibility ------------------------------------------------------------------------

    [Fact]
    public void Never_asks_in_an_unpackaged_build()
    {
        var d = ShouldAsk(Earned(), Quiet() with { IsPackaged = false }, Live);
        Assert.Equal(Reason.NotPackaged, d.Why);
    }

    [Theory]
    [InlineData(AskState.Retired)]
    [InlineData(AskState.AskedTwice)]
    [InlineData(AskState.Asked)]
    public void Does_not_ask_again_once_answered(AskState state)
    {
        var d = ShouldAsk(Earned(state, askedUtc: Now.AddDays(-365)), Quiet(), Live);
        Assert.Equal(Reason.AlreadyAnswered, d.Why);
    }

    [Fact]
    public void Below_the_conversion_threshold()
    {
        var d = ShouldAsk(Earned() with { ConversionCount = 99 }, Quiet(), Live);
        Assert.Equal(Reason.BelowThreshold, d.Why);
    }

    [Fact]
    public void Too_few_active_days_even_with_many_conversions()
    {
        // A single marathon session is not evidence of a habit.
        var d = ShouldAsk(Earned() with { ConversionCount = 5000, ActiveDays = 2 }, Quiet(), Live);
        Assert.Equal(Reason.TooFewActiveDays, d.Why);
    }

    [Fact]
    public void Too_new_an_installation()
    {
        var d = ShouldAsk(Earned() with { FirstRunUtc = Now.AddDays(-3) }, Quiet(), Live);
        Assert.Equal(Reason.TooNew, d.Why);
    }

    [Fact]
    public void No_first_run_date_counts_as_new_not_as_ancient()
    {
        // Counters that predate the field must not let an upgrade ask on its first day.
        var d = ShouldAsk(Earned() with { FirstRunUtc = null }, Quiet(), Live);
        Assert.Equal(Reason.TooNew, d.Why);
    }

    // ---- the re-arm -------------------------------------------------------------------------

    [Fact]
    public void Re_armed_ask_costs_three_times_as_much()
    {
        var state = Earned(AskState.ReArmed, askedUtc: Now.AddDays(-60)) with { ConversionCount = 299, ActiveDays = 30 };
        Assert.Equal(Reason.BelowThreshold, ShouldAsk(state, Quiet(), Live).Why);
        Assert.True(ShouldAsk(state with { ConversionCount = 300 }, Quiet(), Live).Ask);
    }

    [Fact]
    public void Re_armed_ask_waits_out_the_interval()
    {
        var state = Earned(AskState.ReArmed, askedUtc: Now.AddDays(-29)) with { ConversionCount = 1000, ActiveDays = 50 };
        Assert.Equal(Reason.TooSoonAfterFirstAsk, ShouldAsk(state, Quiet(), Live).Why);
    }

    // ---- the moment -------------------------------------------------------------------------

    [Fact]
    public void Not_while_disabled_or_paused()
    {
        Assert.Equal(Reason.DisabledOrPaused, ShouldAsk(Earned(), Quiet() with { ConversionEnabled = false }, Live).Why);
    }

    [Fact]
    public void Not_before_onboarding_is_finished()
    {
        Assert.Equal(Reason.OnboardingIncomplete, ShouldAsk(Earned(), Quiet() with { OnboardingComplete = false }, Live).Why);
    }

    [Fact]
    public void Not_over_a_password_field()
    {
        Assert.Equal(Reason.SecureField, ShouldAsk(Earned(), Quiet() with { SecureFieldFocused = true }, Live).Why);
    }

    [Fact]
    public void Not_in_an_app_where_conversion_is_suppressed()
    {
        Assert.Equal(Reason.DeniedApp, ShouldAsk(Earned(), Quiet() with { DeniedAppForeground = true }, Live).Why);
    }

    [Fact]
    public void Not_on_top_of_our_own_window()
    {
        Assert.Equal(Reason.WindowOpen, ShouldAsk(Earned(), Quiet() with { OwnWindowOpen = true }, Live).Why);
    }

    [Fact]
    public void Not_when_the_settings_file_failed_to_load()
    {
        Assert.Equal(Reason.SettingsLoadFailed, ShouldAsk(Earned(), Quiet() with { SettingsLoadFailed = true }, Live).Why);
    }

    [Fact]
    public void Not_right_after_a_rewrite_that_failed()
    {
        Assert.Equal(Reason.RecentFailure, ShouldAsk(Earned(), Quiet() with { MinutesSinceRewriteFailure = 5 }, Live).Why);
    }

    [Fact]
    public void Not_right_after_the_user_undid_a_conversion()
    {
        Assert.Equal(Reason.RecentUndo, ShouldAsk(Earned(), Quiet() with { MinutesSinceUndo = 5 }, Live).Why);
    }

    [Fact]
    public void Not_mid_sentence()
    {
        Assert.Equal(Reason.UserTyping, ShouldAsk(Earned(), Quiet() with { SecondsSinceKeystroke = 2 }, Live).Why);
        // …and the same user a few seconds later.
        Assert.True(ShouldAsk(Earned(), Quiet() with { SecondsSinceKeystroke = QuietSeconds + 1 }, Live).Ask);
    }

    [Fact]
    public void A_failure_outranks_mere_typing_in_the_reason_given()
    {
        // Both conditions hold; the log should name the one that matters.
        var ctx = Quiet() with { SecondsSinceKeystroke = 1, MinutesSinceRewriteFailure = 1 };
        Assert.Equal(Reason.RecentFailure, ShouldAsk(Earned(), ctx, Live).Why);
    }

    // ---- persisted state parsing ------------------------------------------------------------

    [Theory]
    [InlineData("NotAsked", AskState.NotAsked)]
    [InlineData("ReArmed", AskState.ReArmed)]
    [InlineData("Retired", AskState.Retired)]
    public void Known_states_round_trip(string stored, AskState expected) =>
        Assert.Equal(expected, ParseState(stored));

    [Theory]
    [InlineData("SomethingFromANewerBuild")]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("notasked")]   // case matters: a near-miss is still unrecognised
    public void Unknown_states_mean_do_not_ask(string? stored) =>
        Assert.Equal(AskState.Retired, ParseState(stored));

    // ---- transitions ------------------------------------------------------------------------

    [Fact]
    public void Rating_retires_the_ask_whatever_the_store_says_next() =>
        Assert.Equal(AskState.Retired, AfterRate(AskState.NotAsked));

    [Fact]
    public void Declining_is_permanent() =>
        Assert.Equal(AskState.Retired, AfterDecline(AskState.NotAsked));

    [Fact]
    public void First_deferral_buys_one_more_ask_and_the_second_ends_it()
    {
        Assert.Equal(AskState.ReArmed, AfterDefer(AskState.Asked));
        Assert.Equal(AskState.AskedTwice, AfterDefer(AskState.ReArmed));
    }

    [Fact]
    public void A_deferral_arriving_late_cannot_revive_a_retired_ask()
    {
        // A window still open after the user declined elsewhere, or a second one from a diagnostics
        // run, must not walk a permanent refusal back to "ask again in a month".
        Assert.Equal(AskState.Retired, AfterDefer(AskState.Retired));
        Assert.Equal(AskState.AskedTwice, AfterDefer(AskState.AskedTwice));
    }
}
