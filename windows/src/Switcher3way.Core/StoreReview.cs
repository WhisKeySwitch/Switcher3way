namespace Switcher3way.Core;

/// <summary>
/// Whether to ask this user to rate the app, and if not, why not.
///
/// It lives in Core, next to the detection logic rather than in the app, for the reason Core exists at
/// all: a decision with fourteen ways to say no is exactly the shape of code that is never exercised
/// and silently always-false, and here it can be asserted without the app, its package identity, or a
/// Store licence. Nothing in this file touches Windows.
///
/// <b>It ships unarmed.</b> <see cref="Thresholds.Calibrated"/> is false and
/// <see cref="Reason.Uncalibrated"/> declines before anything else is considered, because no field data
/// exists to set a threshold from: 48 days of development log held 25 applied conversions, every one of
/// them a test word, on 6 days — and the log only exists on days somebody switched debug logging on.
/// The counters this reads run with logging off, so an ordinary month of use produces the number that
/// is missing, and arming is then this one flag plus two values.
/// </summary>
public static class StoreReview
{
    /// <summary>How far the ask has got. Terminal states are <see cref="Retired"/> and <see cref="AskedTwice"/>.</summary>
    public enum AskState
    {
        /// <summary>Never asked.</summary>
        NotAsked,
        /// <summary>Asked once; the user deferred or has not answered.</summary>
        Asked,
        /// <summary>The user deferred, and one further ask is allowed at a higher threshold.</summary>
        ReArmed,
        /// <summary>The second and final ask has been shown.</summary>
        AskedTwice,
        /// <summary>The user rated, or declined permanently. Never ask again.</summary>
        Retired,
    }

    /// <summary>
    /// Parse a persisted state. An unrecognised value — a state written by a newer build, or a corrupted
    /// file — reads as <see cref="AskState.Retired"/>, so the failure mode is "never asks" rather than
    /// "asks repeatedly". Of the two ways to be wrong about a once-ever prompt, only one is recoverable
    /// by the user.
    /// </summary>
    public static AskState ParseState(string? stored) =>
        Enum.TryParse<AskState>(stored, ignoreCase: false, out var s) ? s : AskState.Retired;

    /// <summary>
    /// The counts and ask-state that persist between runs.
    ///
    /// There is deliberately no "armed" flag. Eligibility is re-derived from the counters on every
    /// check, so a threshold crossed in one session is still crossed in the next — a pending ask
    /// survives a restart without anything being stored to say so, and there is no second piece of
    /// state to fall out of step with the counts.
    /// </summary>
    public sealed record State(
        int ConversionCount,
        int ActiveDays,
        DateTime? FirstRunUtc,
        AskState Ask,
        DateTime? AskedUtc);

    /// <summary>Everything read live at the moment of the decision.</summary>
    public sealed record Context(
        DateTime NowUtc,
        bool IsPackaged,
        bool ConversionEnabled,
        bool OnboardingComplete,
        bool SecureFieldFocused,
        bool DeniedAppForeground,
        bool OwnWindowOpen,
        bool SettingsLoadFailed,
        double SecondsSinceKeystroke,
        double MinutesSinceRewriteFailure,
        double MinutesSinceUndo);

    /// <summary>
    /// When the app has earned the ask. <see cref="Calibrated"/> is the master switch: while it is
    /// false the numbers below are placeholders and the automatic ask cannot fire.
    /// </summary>
    public sealed record Thresholds(
        bool Calibrated,
        int Conversions,
        int ActiveDays,
        int InstallAgeDays,
        int ReArmMultiplier = 3,
        int ReArmIntervalDays = 30)
    {
        /// <summary>
        /// What ships. Set against eight days of continuous macOS field logging (2026-09-29→10-06,
        /// post-1.6.0): 114 fixes over 8 calendar days — 48 automatic, 66 by trigger — on 7 active days.
        ///
        /// The numbers are a judgement checked against that log, not derived from it: one user is a
        /// sample of one, and the heaviest user this app has. What the log can do is falsify, and it
        /// does not. At 14.3 fixes a day, 75 is reached in five days, so for that user the install age
        /// is what binds and the ask lands around day 14; a user at a third of the rate reaches both
        /// constraints together at roughly three weeks, which is where this is aimed.
        ///
        /// Being wrong here is cheap in one direction and not the other. Too high and the ask never
        /// fires, which is the same outcome as not shipping it; too low and it arrives early, where
        /// <see cref="AskState.ReArmed"/> absorbs it — a deferral costs one dialog and re-asks at three
        /// times the threshold. That asymmetry is why these ship as a judgement rather than waiting for
        /// a population measurement that no single install can produce.
        /// </summary>
        public static readonly Thresholds Shipping = new(Calibrated: true, Conversions: 75, ActiveDays: 5, InstallAgeDays: 14);
    }

    /// <summary>Why the app is not asking. A closed set, so the log can be read by matching on a name.</summary>
    public static class Reason
    {
        public const string Uncalibrated = "uncalibrated";
        public const string NotPackaged = "not-packaged";
        public const string AlreadyAnswered = "already-answered";
        public const string BelowThreshold = "below-threshold";
        public const string TooFewActiveDays = "too-few-active-days";
        public const string TooNew = "too-new";
        public const string TooSoonAfterFirstAsk = "too-soon-after-first-ask";
        public const string DisabledOrPaused = "disabled-or-paused";
        public const string OnboardingIncomplete = "onboarding-incomplete";
        public const string SecureField = "secure-field";
        public const string DeniedApp = "denied-app";
        public const string RecentFailure = "recent-failure";
        public const string RecentUndo = "recent-undo";
        public const string UserTyping = "user-typing";
        public const string WindowOpen = "window-open";
        public const string SettingsLoadFailed = "settings-load-failed";
    }

    /// <summary>Ask, or decline with a reason from <see cref="Reason"/>.</summary>
    public sealed record Decision(bool Ask, string? Why)
    {
        public static readonly Decision Yes = new(true, null);
        public static Decision No(string why) => new(false, why);
    }

    /// <summary>Idle gap required before the ask may take focus — it must never land mid-word.</summary>
    public const double QuietSeconds = 20;

    /// <summary>How long after a failed rewrite or an undo the app stays quiet, in minutes.</summary>
    public const double CoolOffMinutes = 60;

    /// <summary>
    /// Has the app earned the ask? Counts and ask-state only — nothing about the current moment, so a
    /// caller can log "the threshold is met, we are waiting for a quiet moment" distinctly from
    /// "nothing to ask about yet".
    /// </summary>
    public static Decision Eligible(State state, Context ctx, Thresholds t)
    {
        if (!t.Calibrated) return Decision.No(Reason.Uncalibrated);
        if (!ctx.IsPackaged) return Decision.No(Reason.NotPackaged);

        switch (state.Ask)
        {
            case AskState.Retired:
            case AskState.AskedTwice:
                return Decision.No(Reason.AlreadyAnswered);
            case AskState.Asked:
                // Shown once and not yet answered either way: nothing further until the user defers,
                // which is what moves the state to ReArmed.
                return Decision.No(Reason.AlreadyAnswered);
        }

        // The second ask costs more than the first, and cannot follow it immediately.
        var multiplier = state.Ask == AskState.ReArmed ? t.ReArmMultiplier : 1;
        if (state.Ask == AskState.ReArmed)
        {
            if (state.AskedUtc is not DateTime asked) return Decision.No(Reason.AlreadyAnswered);
            if ((ctx.NowUtc - asked).TotalDays < t.ReArmIntervalDays) return Decision.No(Reason.TooSoonAfterFirstAsk);
        }

        if (state.ConversionCount < t.Conversions * multiplier) return Decision.No(Reason.BelowThreshold);
        if (state.ActiveDays < t.ActiveDays * multiplier) return Decision.No(Reason.TooFewActiveDays);

        // No first-run date means the counters predate this field; treat the install as new rather than
        // as infinitely old, so an upgrade cannot ask on its first day.
        if (state.FirstRunUtc is not DateTime first) return Decision.No(Reason.TooNew);
        if ((ctx.NowUtc - first).TotalDays < t.InstallAgeDays) return Decision.No(Reason.TooNew);

        return Decision.Yes;
    }

    /// <summary>
    /// Is this a moment at which interrupting is acceptable? Evaluated separately from
    /// <see cref="Eligible"/> because it is checked repeatedly while an armed ask waits for its gap.
    /// </summary>
    public static Decision GoodMoment(Context ctx)
    {
        if (ctx.SettingsLoadFailed) return Decision.No(Reason.SettingsLoadFailed);
        if (!ctx.ConversionEnabled) return Decision.No(Reason.DisabledOrPaused);
        if (!ctx.OnboardingComplete) return Decision.No(Reason.OnboardingIncomplete);
        if (ctx.SecureFieldFocused) return Decision.No(Reason.SecureField);
        if (ctx.DeniedAppForeground) return Decision.No(Reason.DeniedApp);
        if (ctx.OwnWindowOpen) return Decision.No(Reason.WindowOpen);

        // Asking for five stars immediately after mangling a sentence is the worst available moment.
        if (ctx.MinutesSinceRewriteFailure < CoolOffMinutes) return Decision.No(Reason.RecentFailure);
        if (ctx.MinutesSinceUndo < CoolOffMinutes) return Decision.No(Reason.RecentUndo);

        // Last, because it is the one that passes on its own a few seconds later: taking focus
        // mid-word interrupts the user and discards the buffer the next conversion would have used.
        if (ctx.SecondsSinceKeystroke < QuietSeconds) return Decision.No(Reason.UserTyping);

        return Decision.Yes;
    }

    /// <summary>The whole decision: earned, and a reasonable moment to say so.</summary>
    public static Decision ShouldAsk(State state, Context ctx, Thresholds t)
    {
        var earned = Eligible(state, ctx, t);
        return earned.Ask ? GoodMoment(ctx) : earned;
    }

    /// <summary>
    /// Where the ask state goes when the user answers. "Rate it" retires regardless of what the Store
    /// dialog then returns — someone who clicked Rate has given their answer, and whether Microsoft's
    /// dialog succeeded is not their problem.
    /// </summary>
    public static AskState AfterRate(AskState _) => AskState.Retired;

    /// <summary>Permanent decline. No version, interval or usage can undo it.</summary>
    public static AskState AfterDecline(AskState _) => AskState.Retired;

    /// <summary>
    /// Deferral — including dismissing the window without choosing, which is read the forgiving way.
    /// The first deferral buys one further ask; the second ends it.
    ///
    /// A terminal state stays terminal. Without that guard a deferral arriving late — a window still
    /// open after the user declined elsewhere, or a second window from a diagnostics run — would move
    /// <see cref="AskState.Retired"/> back to <see cref="AskState.ReArmed"/> and revive a prompt the
    /// user has permanently refused.
    /// </summary>
    public static AskState AfterDefer(AskState current) => current switch
    {
        AskState.Retired or AskState.AskedTwice => current,
        AskState.ReArmed => AskState.AskedTwice,
        _ => AskState.ReArmed,
    };
}
