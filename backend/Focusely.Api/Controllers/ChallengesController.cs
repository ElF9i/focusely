using System.Security.Claims;
using Focusely.Api.Data;
using Focusely.Api.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Controllers;

public record CreateChallengeDto(string Title, string Type, int TargetMinutes, int DurationHours);
public record ChallengeProg(int Seconds, DateTime? FinishedAtUtc);
public record ChallengeDto(Guid Id, string Title, string Type, int TargetSeconds, DateTime StartsAtUtc,
    DateTime EndsAtUtc, int Participants, bool Joined, int MySeconds, bool Finished, string CreatorName, bool Active);
public record RankDto(int Rank, string Username, int Seconds, bool Finished, bool IsMe);
public record ChallengeDetailDto(ChallengeDto Challenge, List<RankDto> Ranking);

[ApiController, Route("api/challenges"), Authorize]
public class ChallengesController(AppDbContext db) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirstValue("sub")!);

    private async Task<Dictionary<Guid, string>> Names(IEnumerable<Guid> ids)
    {
        var set = ids.Distinct().ToList();
        return await db.Users.Where(u => set.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Username);
    }

    // Progression de chaque participant : seances validees apres son inscription, dans la fenetre du defi
    private async Task<Dictionary<(Guid, Guid), ChallengeProg>> ComputeProgress(
        List<StudyChallenge> list, List<ChallengeParticipant> parts)
    {
        var result = new Dictionary<(Guid, Guid), ChallengeProg>();
        if (list.Count == 0 || parts.Count == 0) return result;

        var userIds = parts.Select(p => p.UserId).Distinct().ToList();
        var minStart = list.Min(c => c.StartsAtUtc);
        var sessions = await db.StudySessions
            .Where(s => userIds.Contains(s.UserId) && s.IsValidated && s.EndedAtUtc != null && s.StartedAtUtc >= minStart)
            .Select(s => new { s.UserId, s.StartedAtUtc, s.EndedAtUtc, s.StudySeconds })
            .ToListAsync();

        var byId = list.ToDictionary(c => c.Id);
        foreach (var p in parts)
        {
            var c = byId[p.ChallengeId];
            var from = p.JoinedAtUtc > c.StartsAtUtc ? p.JoinedAtUtc : c.StartsAtUtc;
            var mine = sessions
                .Where(s => s.UserId == p.UserId && s.StartedAtUtc >= from && s.EndedAtUtc <= c.EndsAtUtc)
                .OrderBy(s => s.EndedAtUtc).ToList();
            var total = 0;
            DateTime? finished = null;
            foreach (var s in mine)
            {
                total += s.StudySeconds;
                if (finished is null && total >= c.TargetSeconds) finished = s.EndedAtUtc;
            }
            result[(c.Id, p.UserId)] = new ChallengeProg(total, finished);
        }
        return result;
    }

    private ChallengeDto Build(StudyChallenge c, List<ChallengeParticipant> parts,
        Dictionary<(Guid, Guid), ChallengeProg> prog, Dictionary<Guid, string> names, DateTime now)
    {
        var joined = parts.Any(p => p.ChallengeId == c.Id && p.UserId == UserId);
        prog.TryGetValue((c.Id, UserId), out var my);
        names.TryGetValue(c.CreatorId, out var creator);
        return new ChallengeDto(c.Id, c.Title, c.Type.ToString(), c.TargetSeconds, c.StartsAtUtc, c.EndsAtUtc,
            parts.Count(p => p.ChallengeId == c.Id), joined, my?.Seconds ?? 0, my?.FinishedAtUtc != null,
            creator ?? "?", c.EndsAtUtc > now);
    }

    [HttpGet]
    public async Task<ActionResult<List<ChallengeDto>>> List()
    {
        var now = DateTime.UtcNow;
        var since = now.AddDays(-7);
        var list = await db.StudyChallenges.Where(c => c.EndsAtUtc > since).ToListAsync();
        var ids = list.Select(c => c.Id).ToList();
        var parts = await db.ChallengeParticipants.Where(p => ids.Contains(p.ChallengeId)).ToListAsync();
        var prog = await ComputeProgress(list, parts);
        var names = await Names(list.Select(c => c.CreatorId));
        var dtos = list.Select(c => Build(c, parts, prog, names, now))
            .OrderByDescending(d => d.Active)
            .ThenBy(d => d.Active ? d.EndsAtUtc.Ticks : -d.EndsAtUtc.Ticks)
            .ToList();
        return Ok(dtos);
    }

    [HttpPost]
    public async Task<ActionResult<ChallengeDto>> Create(CreateChallengeDto dto)
    {
        var title = (dto.Title ?? "").Trim();
        if (title.Length == 0 || title.Length > 40) return BadRequest("Titre requis (40 caracteres max).");
        if (!Enum.TryParse<ChallengeType>(dto.Type, true, out var type)) return BadRequest("Type inconnu.");
        var minutes = Math.Clamp(dto.TargetMinutes, 5, 600);
        var hours = Math.Clamp(dto.DurationHours, 1, 720);

        var now = DateTime.UtcNow;
        var c = new StudyChallenge
        {
            CreatorId = UserId, Title = title, Type = type, TargetSeconds = minutes * 60,
            StartsAtUtc = now, EndsAtUtc = now.AddHours(hours)
        };
        var p = new ChallengeParticipant { ChallengeId = c.Id, UserId = UserId, JoinedAtUtc = now };
        db.StudyChallenges.Add(c);
        db.ChallengeParticipants.Add(p);
        await db.SaveChangesAsync();

        var parts = new List<ChallengeParticipant> { p };
        var names = await Names(new[] { UserId });
        return Ok(Build(c, parts, new Dictionary<(Guid, Guid), ChallengeProg>(), names, now));
    }

    [HttpPost("{id:guid}/join")]
    public async Task<IActionResult> Join(Guid id)
    {
        var c = await db.StudyChallenges.FirstOrDefaultAsync(x => x.Id == id);
        if (c is null) return NotFound("Defi introuvable.");
        var now = DateTime.UtcNow;
        if (c.EndsAtUtc <= now) return BadRequest("Ce defi est termine.");
        if (await db.ChallengeParticipants.AnyAsync(p => p.ChallengeId == id && p.UserId == UserId))
            return Ok();
        db.ChallengeParticipants.Add(new ChallengeParticipant { ChallengeId = id, UserId = UserId, JoinedAtUtc = now });
        await db.SaveChangesAsync();
        return Ok();
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<ChallengeDetailDto>> Detail(Guid id)
    {
        var c = await db.StudyChallenges.FirstOrDefaultAsync(x => x.Id == id);
        if (c is null) return NotFound("Defi introuvable.");
        var now = DateTime.UtcNow;
        var parts = await db.ChallengeParticipants.Where(p => p.ChallengeId == id).ToListAsync();
        var prog = await ComputeProgress(new List<StudyChallenge> { c }, parts);
        var names = await Names(parts.Select(p => p.UserId).Append(c.CreatorId));

        var rows = parts.Select(p =>
        {
            prog.TryGetValue((id, p.UserId), out var pr);
            return new { p.UserId, Seconds = pr?.Seconds ?? 0, Fin = pr?.FinishedAtUtc };
        }).ToList();

        var ordered = c.Type == ChallengeType.SpeedRace
            ? rows.OrderBy(r => r.Fin == null).ThenBy(r => r.Fin).ThenByDescending(r => r.Seconds)
            : rows.OrderByDescending(r => r.Seconds);

        var ranking = ordered.Select((r, i) =>
        {
            names.TryGetValue(r.UserId, out var n);
            return new RankDto(i + 1, n ?? "?", r.Seconds, r.Fin != null, r.UserId == UserId);
        }).ToList();

        return Ok(new ChallengeDetailDto(Build(c, parts, prog, names, now), ranking));
    }
}
