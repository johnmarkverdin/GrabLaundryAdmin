The Admin App is the control panel of the entire Laundry Management System.
Admins can view all laundry orders, assign riders, update order status, set total price, view proof images, and delete completed orders.

Built with Flutter + Supabase.

✨ Admin Features
📦 Manage All Orders

View all orders from all customers

Search by customer, rider, service, order ID, or address

Filter by status (pending, accepted, in_wash, completed, etc.)

Real-time updates from Supabase

👤 Rider Assignment

Load list of riders from profiles table where role = 'rider'

Assign or change rider for any order

Rider instantly sees new order in the Rider app

🔄 Update Order Status

Change status manually:

pending

accepted

picked_up

in_wash

in_delivery

completed

cancelled

🧾 Billing

Admin can set or update total_price

Customer will automatically see the updated bill in their app

📷 Proof of Billing

View uploaded proof image

Opens in a modal popup

🗑 Delete Completed Orders

Delete order

Confirmation dialog

RLS allows only admin to delete

🗄 Database Tables Used
profiles

Stores riders, customers, and admins
Fields used in Admin:

id

full_name

phone

role

laundry_orders

Core order table
Fields used:

customer_id

rider_id

service

payment_method

pickup_address

delivery_address

schedule (pickup/delivery datetime)

proof_of_billing_url

status

total_price

🔐 Supabase Permissions (Admin)

Admin is identified by:

profiles.role = 'admin'


Admin policies:

create policy "admin_select_all_orders"
on laundry_orders for select
using (auth.uid() in (select id from profiles where role='admin'));

create policy "admin_modify_all_orders"
on laundry_orders for all
using (auth.uid() in (select id from profiles where role='admin'))
with check (auth.uid() in (select id from profiles where role='admin'));

▶️ How to Run Admin App
1. Install Flutter packages
   flutter pub get

2. Add Supabase Credentials

Inside lib/supabase_config.dart:

await Supabase.initialize(
url: "https://<YOUR-PROJECT>.supabase.co",
anonKey: "<YOUR-ANON-KEY>",
);

3. Run the app
   flutter run


Admin dashboard will load.