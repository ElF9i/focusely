using System.Security.Claims;
using Focusely.Api.Data;
using Focusely.Api.Dtos;
using Focusely.Api.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Focusely.Api.Controllers;

[ApiController, Route("api/subjects"), Authorize]
public class SubjectsController(AppDbContext db) : ControllerBase
{
    private Guid UserId => Guid.Parse(User.FindFirstValue("sub")!);

    [HttpGet]
    public async Task<ActionResult<List<SubjectDto>>> List()
    {
        var list = await db.Subjects.Where(s => s.UserId == UserId)
            .OrderBy(s => s.CreatedAtUtc).ToListAsync();
        return Ok(list.Select(s => new SubjectDto(s.Id, s.Name, s.Color, s.Emoji)).ToList());
    }

    [HttpPost]
    public async Task<ActionResult<SubjectDto>> Create(CreateSubjectDto dto)
    {
        var name = (dto.Name ?? "").Trim();
        if (name.Length == 0 || name.Length > 40) return BadRequest("Nom requis (40 caracteres max).");
        if (await db.Subjects.AnyAsync(s => s.UserId == UserId && s.Name == name))
            return Conflict("Cette matiere existe deja.");

        var s = new Subject
        {
            UserId = UserId, Name = name,
            Color = string.IsNullOrWhiteSpace(dto.Color) ? "#8B7CFF" : dto.Color!,
            Emoji = string.IsNullOrWhiteSpace(dto.Emoji) ? "\U0001F4D8" : dto.Emoji!
        };
        db.Subjects.Add(s);
        await db.SaveChangesAsync();
        return Ok(new SubjectDto(s.Id, s.Name, s.Color, s.Emoji));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var s = await db.Subjects.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (s is null) return NotFound();
        db.Subjects.Remove(s);          // les seances gardent leur temps (SubjectId passe a null)
        await db.SaveChangesAsync();
        return NoContent();
    }
}
