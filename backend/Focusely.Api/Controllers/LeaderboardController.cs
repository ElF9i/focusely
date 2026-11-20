using System.Security.Claims;
using Focusely.Api.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Controllers;

public record LeaderEntry(int Rank, string Username, int Seconds, bool IsMe);
public record LeaderboardDto(int MyRank, int MySeconds, List<LeaderEntry> Entries);

[ApiController, Route("api/leaderboard"), Authorize]
public class LeaderboardController(AppDbContext db) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirstValue("sub")!);

    // Classement de la semaine en cours (lundi = debut), selon le fuseau du telephone
    [HttpGet("weekly")]
    public async Task<ActionResult<LeaderboardDto>> Weekly([FromQuery] int tz = 0)
    {
        var offset = TimeSpan.FromMinutes(Math.Clamp(tz, -840, 840));
        var today = (DateTime.UtcNow + offset).Date;
        var weekStartLocal = today.AddDays(-(((int)today.DayOfWeek + 6) % 7));
        var weekStartUtc = DateTime.SpecifyKind(weekStartLocal - offset, DateTimeKind.Utc);

        var totals = await db.StudySessions
            .Where(s => s.IsValidated && s.EndedAtUtc != null && s.StartedAtUtc >= weekStartUtc)
            .GroupBy(s => s.UserId)
            .Select(g => new { UserId = g.Key, Seconds = g.Sum(x => x.StudySeconds) })
            .ToListAsync();

        var all = totals.OrderByDescending(t => t.Seconds).ToList();
        var top = all.Take(20).ToList();
        var ids = top.Select(t => t.UserId).ToList();
        var names = await db.Users.Where(u => ids.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Username);

        var entries = top.Select((t, i) =>
        {
            names.TryGetValue(t.UserId, out var n);
            return new LeaderEntry(i + 1, n ?? "?", t.Seconds, t.UserId == UserId);
        }).ToList();

        var myIndex = all.FindIndex(t => t.UserId == UserId);
        return Ok(new LeaderboardDto(myIndex < 0 ? 0 : myIndex + 1, myIndex < 0 ? 0 : all[myIndex].Seconds, entries));
    }
}
