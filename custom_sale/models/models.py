import base64
import locale
from io import BytesIO

from odoo import fields, models, api


class SaleOrderCustom(models.Model):
    _inherit = 'sale.order'

    payment_terms = fields.Many2one(comodel_name="account.payment.term", string="Payment Terms", store=True)
    delivery_terms = fields.Char(string="Delivery Terms", store=True)

    def _default_reference(self):
        proformaList = self.env['sale.order'].sudo().search_count([])
        return 10023 + proformaList + 1

    quotation_date = fields.Date(string="Date", default=fields.Date.today())
    proforma_sequence = fields.Integer(string="Proforma Sequence", default=_default_reference)

    @api.multi
    def print_quotation(self):
        return self.env.ref('custom_sale.proforma_invoice_print_pdf_id').report_action(self)

    @api.model
    def company_info(self):
        company = self.env.user.company_id
        logo_data = base64.b64decode(company.logo)
        return {
            'name': company.name,
            'vat': company.vat,
            'vrn': company.company_registry,
            'street': company.street,
            'street2': company.street2,
            'phone': company.phone,
            'email': company.email,
            'website': company.website,
            'logo': BytesIO(logo_data)
        }


class InheritProductTemplate(models.Model):
    _inherit = 'product.template'

    uom_id = fields.Many2one('uom.uom', string='Unit of Measure', required=True)


class AccountInvoice(models.Model):
    _inherit = 'account.invoice'

    def get_payment_dates(self):
        payment_dates = []
        for payment in self.payment_ids:
            if payment.payment_date:
                payment_dates.append(payment.payment_date)
        return payment_dates

    def format_payment_amount(self, amount):
        return locale.format('%.2f', amount, grouping=True)

    def get_payment_amount(self):
        payment_amount = []
        for payment in self.payment_ids:
            if payment.payment_date:
                payment_amount.append(payment.amount)
        return payment_amount

    @api.multi
    def action_print_invoice(self):
        return self.env.ref('custom_sale.invoice_print_pdf_id').report_action(self)

    @api.model
    def company_info(self):
        company = self.env.user.company_id
        logo_data = base64.b64decode(company.logo)
        return {
            'name': company.name,
            'vat': company.vat,
            'vrn': company.company_registry,
            'street': company.street,
            'street2': company.street2,
            'phone': company.phone,
            'email': company.email,
            'website': company.website,
            'logo': BytesIO(logo_data)
        }


class CustomSaleOrderLine(models.Model):
    _inherit = 'sale.order.line'

    unit_measures = fields.Char(string='Unit of Measure', required=False)


# class StockPickingInherit(models.Model):
#     _inherit = 'stock.picking'
#
#     # = fields.Many2one('res.users', string='User', default=lambda self: self.env.user)
#     sale_person_user_id = fields.Many2one('res.users', string='Salesperson', track_visibility='onchange',
#                                           readonly=True, states={'draft': [('readonly', False)]},
#                                           default=lambda self: self.env.user, copy=False)
#
#     @api.model
#     def company_info(self):
#         company = self.env.user.company_id
#         logo_data = base64.b64decode(company.logo)
#         return {
#             'name': company.name,
#             'vat': company.vat,
#             'vrn': company.company_registry,
#             'street': company.street,
#             'street2': company.street2,
#             'phone': company.phone,
#             'email': company.email,
#             'website': company.website,
#             'logo': BytesIO(logo_data)
#         }
#
#     @api.multi
#     def print_delivery_note_action(self):
#         return self.env.ref('custom_sale.delivery_note_print_pdf_id').report_action(self)
#
#     @api.multi
#     def return_to_draft(self):
#         self.write({'state': 'draft'})
#         return True


class ResPartnerInherit(models.Model):
    _inherit = "res.partner"

    # vrn = fields.Char(string="VRN")
    vrn = fields.Char(string="VRN")
