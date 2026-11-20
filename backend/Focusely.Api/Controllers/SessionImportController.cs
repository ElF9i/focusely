using System.Security.Claims;
using Focusely.Api.Data;
using Focusely.Api.Dtos;
using Focusely.Api.Models;
using Focusely.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Controllers;

// Synchronisation des seances terminees hors-ligne.
// Idempotent : le meme Id envoye deux fois ne compte qu'une fois.
[ApiController, Route("api/sessions"), Authorize]
public class SessionImportController(AppDbContext db) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirstValue("sub")!);

    private const int MaxSessionSeconds = 12 * 3600;   // RG03 : une seance ne depasse pas 12 h
    private const int MaxAgeDays = 30;                  // seances trop anciennes refusees
    private static readonly TimeSpan FutureTolerance = TimeSpan.FromMinutes(2);

    private static DateTime Utc(DateTime d) =>
        d.Kind == DateTimeKind.Unspecified ? DateTime.SpecifyKind(d, DateTimeKind.Utc) : d.ToUniversalTime();

    [HttpPost("import")]
    public async Task<ActionResult<SessionDto>> Import(ImportSessionDto dto)
    {
        var now = DateTime.UtcNow;
        var start = Utc(dto.StartedAtUtc);
        var end = Utc(dto.EndedAtUtc);

        // ---- RG03 : controles anti-fraude ----
        if (end <= start) return BadRequest("Duree negative ou nulle.");
        if (start > now + FutureTolerance || end > now + FutureTolerance)
            return BadRequest("Horodatage dans le futur.");
        if (start < now.AddDays(-MaxAgeDays)) return BadRequest("Seance trop ancienne.");
        var total = (int)(end - start).TotalSeconds;
        if (total > MaxSessionSeconds) return BadRequest("Seance trop longue (12 h max).");
        if (dto.PausedSeconds < 0 || dto.PausedSeconds > total) return BadRequest("Pauses incoherentes.");

        var existing = await db.StudySessions.FirstOrDefaultAsync(s => s.Id == dto.Id);
        if (existing is not null && existing.UserId != UserId) return Conflict("Identifiant deja utilise.");
        if (existing is not null && existing.EndedAtUtc is not null)
            return Ok(existing.ToDto());                       // deja synchronisee : pas de double comptage

        // Pas de chevauchement avec une autre seance du meme utilisateur
        var overlap = await db.StudySessions.AnyAsync(s =>
            s.UserId == UserId && s.Id != dto.Id &&
            s.StartedAtUtc < end && (s.EndedAtUtc ?? now) > start);
        if (overlap) return Conflict("Chevauche une autre seance.");

        Guid? subjectId = dto.SubjectId;
        if (subjectId is not null && !await db.Subjects.AnyAsync(x => x.Id == subjectId && x.UserId == UserId))
            subjectId = null;

        var s = existing ?? new StudySession { Id = dto.Id, UserId = UserId };
        s.Mode = dto.Mode;
        s.SubjectId = subjectId;
        s.TargetSeconds = dto.TargetSeconds;
        s.StartedAtUtc = start;
        s.PausedAtUtc = null;
        s.PausedSeconds = dto.PausedSeconds;
        s.EndedAtUtc = end;
        s.StudySeconds = Math.Max(0, total - dto.PausedSeconds);
        s.IsValidated = s.StudySeconds >= Focusely.Api.Services.SessionExtensions.MinValidSeconds;
        if (existing is null) db.StudySessions.Add(s);
        await db.SaveChangesAsync();
        return Ok(s.ToDto());
    }
}
