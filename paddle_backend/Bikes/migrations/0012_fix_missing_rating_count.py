from django.db import migrations


def add_rating_count_if_missing(apps, schema_editor):
    db = schema_editor.connection
    with db.cursor() as cursor:
        cursor.execute("PRAGMA table_info(Bikes_bikes)")
        columns = [row[1] for row in cursor.fetchall()]
        if 'rating_count' not in columns:
            cursor.execute(
                "ALTER TABLE Bikes_bikes ADD COLUMN rating_count INTEGER NOT NULL DEFAULT 0"
            )


class Migration(migrations.Migration):

    dependencies = [
        ('Bikes', '0011_bikes_bike_address_bikes_rating_count'),
    ]

    operations = [
        migrations.RunPython(add_rating_count_if_missing, migrations.RunPython.noop),
    ]
