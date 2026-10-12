export default function Page() {
  return (
    <main className="mx-auto w-full space-y-6 p-6">
      <div className="space-y-1">
        <h1 className="type-page-title">UniExam Admin</h1>
        <p className="type-description text-muted-foreground">
          Foundation check. This page is temporary.
        </p>
      </div>

      <section className="space-y-3 rounded-lg border bg-card p-4 text-card-foreground">
        <h2 className="type-card-title">Tokens and type</h2>
        <p className="type-body text-muted-foreground">
          Body text in the muted colour on a card surface.
        </p>
        <div className="flex flex-wrap gap-2">
          <span className="type-meta rounded-md bg-primary px-2 py-1 text-primary-foreground">
            Primary
          </span>
          <span className="type-meta rounded-md bg-success-muted px-2 py-1 text-success-muted-foreground">
            Success
          </span>
          <span className="type-meta rounded-md bg-warning-muted px-2 py-1 text-warning-muted-foreground">
            Warning
          </span>
          <span className="type-meta rounded-md bg-info-muted px-2 py-1 text-info-muted-foreground">
            Info
          </span>
          <span className="type-meta rounded-md bg-destructive-muted px-2 py-1 text-destructive-muted-foreground">
            Destructive
          </span>
        </div>
        <p className="type-helper text-muted-foreground">
          Real status badges will pair an icon or label with colour.
        </p>
      </section>
    </main>
  );
}
