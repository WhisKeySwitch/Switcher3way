using System.Drawing;
using System.Windows.Forms;

namespace Switcher3way.App;

/// <summary>
/// The single update dialog — Install and Relaunch / Later / Skip This Version — mirroring the
/// macOS NSAlert. Shows the release notes (truncated) below the version line.
/// </summary>
internal sealed class UpdatePromptForm : Form
{
    public enum Choice { Install, Later, Skip }

    public Choice Result { get; private set; } = Choice.Later;

    private UpdatePromptForm(UpdateInfo info, string current)
    {
        Text = "Switcher3way";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 9f);
        ClientSize = new Size(460, 340);
        try { Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!); } catch { /* dev host */ }

        var title = new Label
        {
            Text = Loc.Tf("update.available.title", info.Version),
            Font = new Font("Segoe UI", 12f, FontStyle.Bold),
            Location = new Point(16, 16), AutoSize = true, MaximumSize = new Size(428, 0),
        };
        var sub = new Label
        {
            Text = Loc.Tf("update.installed", current),
            ForeColor = SystemColors.GrayText,
            Location = new Point(16, 46), AutoSize = true,
        };
        var notes = new TextBox
        {
            Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
            Location = new Point(16, 74), Size = new Size(428, 214),
            BackColor = SystemColors.Window,
            Text = (info.Notes ?? "").Trim().Replace("\n", "\r\n"),
        };
        notes.Select(0, 0);

        var install = new Button { Text = Loc.T("update.install"), Location = new Point(16, 300), Size = new Size(150, 28), DialogResult = DialogResult.OK };
        var later = new Button { Text = Loc.T("update.later"), Location = new Point(258, 300), Size = new Size(80, 28), DialogResult = DialogResult.Cancel };
        var skip = new Button { Text = Loc.T("update.skip"), Location = new Point(344, 300), Size = new Size(100, 28) };
        install.Click += (_, _) => { Result = Choice.Install; };
        later.Click += (_, _) => { Result = Choice.Later; };
        skip.Click += (_, _) => { Result = Choice.Skip; Close(); };

        AcceptButton = install;
        CancelButton = later;
        Controls.AddRange(new Control[] { title, sub, notes, install, later, skip });
    }

    /// <summary>Show the dialog modally and return the user's choice.</summary>
    public static Choice Ask(UpdateInfo info, string current)
    {
        using var f = new UpdatePromptForm(info, current);
        f.ShowDialog();
        return f.Result;
    }
}
