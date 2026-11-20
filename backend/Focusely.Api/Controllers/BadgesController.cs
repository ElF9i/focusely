using System.Security.Claims;
using Focusely.Api.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Controllers;

public record BadgeDto(string Code, string Name, string Emoji, string Description, bool Unlocked, int Progress, int Target);

[ApiController, Route("api/badges"), Authorize]
public class BadgesController(AppDbContext db) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirstValue("sub")!);
    private const int StreakMinSeconds = 600;

    // Les badges sont calcules a la volee a partir des seances validees (aucune table)
    [HttpGet]
    public async Task<ActionResult<List<BadgeDto>>> List([FromQuery] int tz = 0)
    {
        var offset = TimeSpan.FromMinutes(Math.Clamp(tz, -840, 840));
        var raw = await db.StudySessions
            .Where(s => s.UserId == UserId && s.IsValidated && s.EndedAtUtc != null)
            .Select(s => new { s.StartedAtUtc, s.StudySeconds })
            .ToListAsync();

        var count = raw.Count;
        var total = raw.Sum(r => r.StudySeconds);
        var longest = count == 0 ? 0 : raw.Max(r => r.StudySeconds);
        var xp = raw.Sum(r => (r.StudySeconds / 60) * 2 + 10);
        var level = (int)Math.Floor(Math.Sqrt(xp / 50.0)) + 1;
        var night = raw.Count(r => { var h = (r.StartedAtUtc + offset).Hour; return h >= 22 || h < 5; });
        var early = raw.Count(r => { var h = (r.StartedAtUtc + offset).Hour; return h >= 5 && h < 8; });

        var goodDays = raw.GroupBy(r => (r.StartedAtUtc + offset).Date)
            .Where(g => g.Sum(x => x.StudySeconds) >= StreakMinSeconds)
            .Select(g => g.Key).OrderBy(d => d).ToList();
        var best = 0;
        var run = 0;
        DateTime? prev = null;
        foreach (var d in goodDays)
        {
            run = prev is not null && (d - prev.Value).Days == 1 ? run + 1 : 1;
            best = Math.Max(best, run);
            prev = d;
        }

        BadgeDto B(string code, string name, string emoji, string desc, int progress, int target) =>
            new(code, name, emoji, desc, progress >= target, Math.Min(progress, target), target);

        var list = new List<BadgeDto>
        {
            B("first_session", "Premier pas", "\U0001F331", "Termine ta premi\u00E8re s\u00E9ance", count, 1),
            B("sessions_10", "R\u00E9gulier", "\U0001F4D8", "10 s\u00E9ances valid\u00E9es", count, 10),
            B("sessions_50", "Assidu", "\U0001F393", "50 s\u00E9ances valid\u00E9es", count, 50),
            B("hours_1", "Une heure", "\u23F1", "1 h d'\u00E9tude au total", total, 3600),
            B("hours_10", "Dix heures", "\u231B", "10 h d'\u00E9tude au total", total, 36000),
            B("hours_50", "Endurant", "\U0001F4AA", "50 h d'\u00E9tude au total", total, 180000),
            B("hours_100", "L\u00E9gende", "\U0001F451", "100 h d'\u00E9tude au total", total, 360000),
            B("streak_3", "En route", "\U0001F525", "3 jours de s\u00E9rie", best, 3),
            B("streak_7", "Semaine parfaite", "\u26A1", "7 jours de s\u00E9rie", best, 7),
            B("streak_30", "Inarr\u00EAtable", "\U0001F3C6", "30 jours de s\u00E9rie", best, 30),
            B("marathon", "Marathon", "\U0001F3C3", "Une s\u00E9ance de 2 h", longest, 7200),
            B("night_owl", "Noctambule", "\U0001F989", "5 s\u00E9ances apr\u00E8s 22 h", night, 5),
            B("early_bird", "L\u00E8ve-t\u00F4t", "\U0001F305", "5 s\u00E9ances entre 5 h et 8 h", early, 5),
            B("level_5", "Niveau 5", "\u2B50", "Atteins le niveau 5", level, 5),
        };
        return Ok(list);
    }
}
