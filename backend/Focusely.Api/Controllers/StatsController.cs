using System.Security.Claims;
using Focusely.Api.Data;
using Focusely.Api.Dtos;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Controllers;

[ApiController, Route("api/stats"), Authorize]
public class StatsController(AppDbContext db) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirstValue("sub")!);
    private const int StreakMinSeconds = 600;   // 10 min d'etude validee par jour pour la serie

    // tz = decalage du fuseau du telephone par rapport a UTC, en minutes (Tunis = 60)
    [HttpGet("dashboard")]
    public async Task<ActionResult<StatsDto>> Dashboard([FromQuery] int tz = 0)
    {
        tz = Math.Clamp(tz, -840, 840);
        var offset = TimeSpan.FromMinutes(tz);

        var raw = await db.StudySessions
            .Where(s => s.UserId == UserId && s.IsValidated && s.EndedAtUtc != null)
            .Select(s => new { s.StartedAtUtc, s.StudySeconds, s.SubjectId })
            .ToListAsync();

        var rows = raw.Select(r => new { Day = (r.StartedAtUtc + offset).Date, r.StudySeconds, r.SubjectId }).ToList();
        var today = (DateTime.UtcNow + offset).Date;

        var perDay = rows.GroupBy(r => r.Day).ToDictionary(g => g.Key, g => g.Sum(x => x.StudySeconds));
        int Get(DateTime d) => perDay.TryGetValue(d, out var v) ? v : 0;
        int SumFrom(DateTime from) => perDay.Where(kv => kv.Key >= from && kv.Key <= today).Sum(kv => kv.Value);

        var weekStart = today.AddDays(-(((int)today.DayOfWeek + 6) % 7));
        var monthStart = new DateTime(today.Year, today.Month, 1);

        // Serie : jours consecutifs >= 10 min, en partant d'aujourd'hui (ou d'hier si rien aujourd'hui)
        var streak = 0;
        var cursor = Get(today) >= StreakMinSeconds ? today : today.AddDays(-1);
        while (Get(cursor) >= StreakMinSeconds) { streak++; cursor = cursor.AddDays(-1); }

        // XP : 2 par minute + 10 par seance validee. Niveau N commence a 50*(N-1)^2 XP.
        var xp = rows.Sum(r => (r.StudySeconds / 60) * 2 + 10);
        var level = (int)Math.Floor(Math.Sqrt(xp / 50.0)) + 1;
        var levelXp = 50 * (level - 1) * (level - 1);
        var nextXp = 50 * level * level;

        var days = Enumerable.Range(0, 35)
            .Select(i => today.AddDays(i - 34))
            .Select(d => new DayStat(d.ToString("yyyy-MM-dd"), Get(d)))
            .ToList();

        var subjects = await db.Subjects.Where(s => s.UserId == UserId).ToDictionaryAsync(s => s.Id);
        var since = today.AddDays(-29);
        var bySubject = rows.Where(r => r.Day >= since)
            .GroupBy(r => r.SubjectId)
            .Select(g =>
            {
                Models.Subject? sub = null;
                if (g.Key is Guid id) subjects.TryGetValue(id, out sub);
                return new SubjectStat(g.Key,
                    sub?.Name ?? "Sans mati\u00E8re", sub?.Color ?? "#9AA0B4", sub?.Emoji ?? "\U0001F4DA",
                    g.Sum(x => x.StudySeconds));
            })
            .OrderByDescending(x => x.Seconds)
            .ToList();

        return Ok(new StatsDto(Get(today), SumFrom(weekStart), SumFrom(monthStart), rows.Sum(r => r.StudySeconds),
            rows.Count, streak, xp, level, levelXp, nextXp, days, bySubject));
    }
}
